/*
 * Azeroth Control Bridge
 * Copyright (C) 2026 Azeroth Control contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "Chat.h"
#include "Group.h"
#include "GroupMgr.h"
#include "LFG.h"
#include "ObjectAccessor.h"
#include "Opcodes.h"
#include "Player.h"
#include "PlayerbotAI.h"
#include "PlayerbotAIConfig.h"
#include "PlayerbotFactory.h"
#include "Playerbots.h"
#include "RandomPlayerbotMgr.h"
#include "ScriptMgr.h"
#include "UseMeetingStoneAction.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using namespace Acore::ChatCommands;

namespace
{
struct PartySlot
{
    uint8 classId = 0;
    uint8 specId = 0;
};

enum class PartyRole
{
    Tank,
    Healer,
    Damage
};

bool IsSafeToken(std::string const& value, std::size_t maximum, bool allowDash = false)
{
    if (value.empty() || value.size() > maximum)
        return false;

    return std::all_of(value.begin(), value.end(), [allowDash](unsigned char character) {
        return std::isalnum(character) || (allowDash && character == '-');
    });
}

std::vector<std::string> Split(std::string const& value, char separator)
{
    std::vector<std::string> fields;
    std::stringstream stream(value);
    std::string field;
    while (std::getline(stream, field, separator))
        fields.push_back(field);
    return fields;
}

bool ParseSlots(std::string const& encoded, std::vector<PartySlot>& slots)
{
    std::vector<std::string> const entries = Split(encoded, ',');
    if (entries.empty() || entries.size() > 4)
        return false;

    for (std::string const& entry : entries)
    {
        std::vector<std::string> const fields = Split(entry, ':');
        if (fields.size() != 2 || !IsSafeToken(fields[0], 2) || !IsSafeToken(fields[1], 2))
            return false;

        unsigned long const classId = std::strtoul(fields[0].c_str(), nullptr, 10);
        unsigned long const specId = std::strtoul(fields[1].c_str(), nullptr, 10);
        if (classId >= MAX_CLASSES || specId >= MAX_SPECNO || classId == 0 || classId == 10)
            return false;
        if (sPlayerbotAIConfig.premadeSpecName[classId][specId].empty())
            return false;

        slots.push_back({static_cast<uint8>(classId), static_cast<uint8>(specId)});
    }
    return true;
}

bool GroupHasOtherHuman(Group* group, Player* leader)
{
    if (!group)
        return false;

    for (GroupReference* reference = group->GetFirstMember(); reference; reference = reference->next())
    {
        Player* const member = reference->GetSource();
        if (member && member != leader && !GET_PLAYERBOT_AI(member))
            return true;
    }
    return false;
}

bool BotCanBeReserved(Player* bot, Player* leader)
{
    if (!bot || !leader || !bot->GetSession() || !bot->IsInWorld())
        return false;
    if (!sRandomPlayerbotMgr.IsRandomBot(bot) || bot->GetTeamId() != leader->GetTeamId())
        return false;
    if (bot->IsInCombat() || bot->InBattleground() || bot->InBattlegroundQueue() || bot->IsBeingTeleported() || bot->IsInFlight())
        return false;

    PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
    if (!botAI || (botAI->HasGameClientMaster() && botAI->GetMaster() != leader))
        return false;

    Group* const group = bot->GetGroup();
    return !group || group == leader->GetGroup() || !GroupHasOtherHuman(group, nullptr);
}

Player* ReserveBot(Player* leader, PartySlot const& slot, std::set<ObjectGuid> const& alreadyReserved)
{
    std::vector<Player*> candidates;
    PlayerBotMap const bots = sRandomPlayerbotMgr.GetAllBots();
    for (auto const& entry : bots)
    {
        Player* const bot = entry.second;
        if (!BotCanBeReserved(bot, leader) || bot->getClass() != slot.classId || alreadyReserved.count(bot->GetGUID()))
            continue;
        candidates.push_back(bot);
    }

    std::stable_sort(candidates.begin(), candidates.end(), [leader](Player* left, Player* right) {
        bool const leftAlreadyGrouped = left->GetGroup() && left->GetGroup() == leader->GetGroup();
        bool const rightAlreadyGrouped = right->GetGroup() && right->GetGroup() == leader->GetGroup();
        if (leftAlreadyGrouped != rightAlreadyGrouped)
            return leftAlreadyGrouped;
        int const leftDistance = std::abs(static_cast<int>(left->GetLevel()) - static_cast<int>(leader->GetLevel()));
        int const rightDistance = std::abs(static_cast<int>(right->GetLevel()) - static_cast<int>(leader->GetLevel()));
        if (leftDistance != rightDistance)
            return leftDistance < rightDistance;
        return left->GetGUID().GetCounter() < right->GetGUID().GetCounter();
    });

    return candidates.empty() ? nullptr : candidates.front();
}

bool SlotForRole(Player* bot, Player* leader, PartyRole role, PartySlot& slot)
{
    uint8 specId = 0;
    switch (role)
    {
        case PartyRole::Tank:
            if (bot->getClass() == CLASS_WARRIOR) specId = 2;
            else if (bot->getClass() == CLASS_PALADIN) specId = 1;
            else if (bot->getClass() == CLASS_DRUID) specId = 1;
            else if (bot->getClass() == CLASS_DEATH_KNIGHT && leader->GetLevel() >= 55) specId = 0;
            else return false;
            break;
        case PartyRole::Healer:
            if (bot->getClass() == CLASS_PRIEST) specId = 0;
            else if (bot->getClass() == CLASS_PALADIN) specId = 0;
            else if (bot->getClass() == CLASS_SHAMAN) specId = 2;
            else if (bot->getClass() == CLASS_DRUID) specId = 2;
            else return false;
            break;
        case PartyRole::Damage:
            switch (bot->getClass())
            {
                case CLASS_WARRIOR: specId = 0; break;
                case CLASS_PALADIN: specId = 2; break;
                case CLASS_HUNTER: specId = 1; break;
                case CLASS_ROGUE: specId = 1; break;
                case CLASS_PRIEST: specId = 2; break;
                case CLASS_DEATH_KNIGHT:
                    if (leader->GetLevel() < 55) return false;
                    specId = 1;
                    break;
                case CLASS_SHAMAN: specId = 0; break;
                case CLASS_MAGE: specId = 2; break;
                case CLASS_WARLOCK: specId = 1; break;
                case CLASS_DRUID: specId = 0; break;
                default: return false;
            }
            break;
    }

    if (sPlayerbotAIConfig.premadeSpecName[bot->getClass()][specId].empty())
        return false;
    slot = {bot->getClass(), specId};
    return true;
}

Player* ReserveBotForRole(Player* leader, PartyRole role, std::set<ObjectGuid> const& alreadyReserved, PartySlot& slot)
{
    struct Candidate
    {
        Player* bot;
        PartySlot slot;
    };
    std::vector<Candidate> candidates;
    PlayerBotMap const bots = sRandomPlayerbotMgr.GetAllBots();
    for (auto const& entry : bots)
    {
        Player* const bot = entry.second;
        PartySlot candidateSlot;
        if (!BotCanBeReserved(bot, leader) || alreadyReserved.count(bot->GetGUID()) || !SlotForRole(bot, leader, role, candidateSlot))
            continue;
        candidates.push_back({bot, candidateSlot});
    }

    std::stable_sort(candidates.begin(), candidates.end(), [leader](Candidate const& left, Candidate const& right) {
        int const leftDistance = std::abs(static_cast<int>(left.bot->GetLevel()) - static_cast<int>(leader->GetLevel()));
        int const rightDistance = std::abs(static_cast<int>(right.bot->GetLevel()) - static_cast<int>(leader->GetLevel()));
        if (leftDistance != rightDistance)
            return leftDistance < rightDistance;
        return left.bot->GetGUID().GetCounter() < right.bot->GetGUID().GetCounter();
    });

    if (candidates.empty())
        return nullptr;
    slot = candidates.front().slot;
    return candidates.front().bot;
}

void PrepareBot(Player* bot, Player* leader, PartySlot const& slot)
{
    PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
    botAI->SetMaster(leader);
    botAI->Reset();

    PlayerbotFactory factory(bot, leader->GetLevel());
    factory.Randomize(false);

    // Randomize initializes the complete level-appropriate spellbook, skills,
    // consumables and gear. Apply the user's requested PvE template afterward,
    // then regenerate equipment so item stats follow the final specialization.
    PlayerbotFactory::InitTalentsBySpecNo(bot, slot.specId, true);
    PlayerbotFactory::DestroyEquippedGear(bot);
    PlayerbotFactory refit(bot, leader->GetLevel());
    refit.InitEquipment(false, true);
    refit.InitAmmo();
    refit.InitGlyphs(false);
    refit.InitPet();
    refit.InitPetTalents();

    bot->DurabilityRepairAll(false, 1.0f, false);
    bot->SetHealth(bot->GetMaxHealth());
    bot->SetPower(POWER_MANA, bot->GetMaxPower(POWER_MANA));
    bot->SendTalentsInfoData(false);
    botAI->ResetStrategies(false);
    bot->SaveToDB(false, false);
}

std::vector<Player*> ManagedPartyBots(Player* leader)
{
    std::vector<Player*> bots;
    Group* const group = leader ? leader->GetGroup() : nullptr;
    if (!group)
        return bots;

    for (GroupReference* reference = group->GetFirstMember(); reference; reference = reference->next())
    {
        Player* const member = reference->GetSource();
        if (member && member != leader && GET_PLAYERBOT_AI(member))
            bots.push_back(member);
    }
    return bots;
}

void PrepareExistingBot(Player* bot, Player* leader)
{
    PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
    if (bot->isDead())
        bot->ResurrectPlayer(1.0f, false);
    bot->CombatStop(true);
    bot->GiveLevel(leader->GetLevel());
    bot->SetUInt32Value(PLAYER_XP, 0);
    bot->InitStatsForLevel(true);

    PlayerbotFactory factory(bot, leader->GetLevel());
    factory.InitSkills();
    factory.InitClassSpells();
    factory.InitAvailableSpells();
    factory.InitSpecialSpells();
    PlayerbotFactory::DestroyEquippedGear(bot);
    factory.InitEquipment(false, true);
    factory.InitAmmo();
    factory.InitGlyphs(false);
    factory.InitPet();
    factory.InitPetTalents();
    factory.InitFood();
    factory.InitReagents();
    factory.InitConsumables();
    factory.InitPotions();

    bot->DurabilityRepairAll(false, 1.0f, false);
    bot->SetHealth(bot->GetMaxHealth());
    bot->SetPower(POWER_MANA, bot->GetMaxPower(POWER_MANA));
    botAI->SetMaster(leader);
    botAI->Reset();
    botAI->ResetStrategies(false);
    bot->SaveToDB(false, false);
}

bool SummonPartyBot(Player* bot, Player* leader)
{
    PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
    botAI->SetMaster(leader);
    SummonAction summon(botAI, "azeroth control party recovery");
    if (summon.Teleport(leader, bot, true))
        return true;
    return bot->TeleportTo(leader->GetMapId(), leader->GetPositionX(), leader->GetPositionY(),
                           leader->GetPositionZ(), leader->GetOrientation());
}

void EmitResult(ChatHandler* handler, std::string const& result)
{
    handler->SendSysMessage(result);
    LOG_INFO("module.azeroth-control", "{}", result);
}

std::string ErrorResult(std::string const& requestId, std::string const& code, std::string const& message)
{
    return "AZC_PARTY_RESULT|" + requestId + "|ERR|" + code + "|" + message;
}
}

class AzerothControlBridgeCommand : public CommandScript
{
public:
    AzerothControlBridgeCommand() : CommandScript("AzerothControlBridgeCommand") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable partyCommands = {
            {"build", HandlePartyBuild, SEC_ADMINISTRATOR, Console::Yes},
            {"summon", HandlePartySummon, SEC_ADMINISTRATOR, Console::Yes},
            {"prepare", HandlePartyPrepare, SEC_ADMINISTRATOR, Console::Yes},
            {"recover", HandlePartyRecover, SEC_ADMINISTRATOR, Console::Yes},
            {"disband", HandlePartyDisband, SEC_ADMINISTRATOR, Console::Yes},
        };
        static ChatCommandTable bridgeCommands = {
            {"party", partyCommands},
        };
        static ChatCommandTable commands = {
            {"azerothcontrol", bridgeCommands},
        };
        return commands;
    }

    static bool HandlePartyBuild(ChatHandler* handler, char const* arguments)
    {
        std::istringstream input(arguments ? arguments : "");
        std::string requestId;
        std::string leaderName;
        std::string encodedSlots;
        input >> requestId >> leaderName >> encodedSlots;

        if (!IsSafeToken(requestId, 32, true))
            return false;
        if (!IsSafeToken(leaderName, 12) || encodedSlots.empty())
        {
            EmitResult(handler, ErrorResult(requestId, "BAD_REQUEST", "Invalid leader or party definition"));
            return true;
        }

        std::vector<PartySlot> slots;
        if (!ParseSlots(encodedSlots, slots) || slots.size() != 4)
        {
            EmitResult(handler, ErrorResult(requestId, "BAD_SLOTS", "Exactly four valid class and specialization slots are required"));
            return true;
        }

        Player* const leader = ObjectAccessor::FindPlayerByName(leaderName, true);
        if (!leader || !leader->GetSession() || GET_PLAYERBOT_AI(leader))
        {
            EmitResult(handler, ErrorResult(requestId, "LEADER_OFFLINE", "The selected player is not online"));
            return true;
        }
        if (leader->IsInCombat() || leader->InBattleground() || leader->InBattlegroundQueue() || leader->IsBeingTeleported() || leader->IsInFlight())
        {
            EmitResult(handler, ErrorResult(requestId, "LEADER_BUSY", "Leave combat, queues, battlegrounds and flight before building the party"));
            return true;
        }
        if (leader->GetGroup() && (leader->GetGroup()->isLFGGroup() || leader->GetGroup()->isBGGroup() || leader->GetGroup()->isBFGroup()))
        {
            EmitResult(handler, ErrorResult(requestId, "SPECIAL_GROUP", "Dungeon finder and battleground groups cannot be replaced"));
            return true;
        }
        if (GroupHasOtherHuman(leader->GetGroup(), leader))
        {
            EmitResult(handler, ErrorResult(requestId, "HUMAN_PARTY", "Leave the current player party before using Party Builder"));
            return true;
        }
        if (leader->GetLevel() < 55 && std::any_of(slots.begin(), slots.end(), [](PartySlot const& slot) { return slot.classId == CLASS_DEATH_KNIGHT; }))
        {
            EmitResult(handler, ErrorResult(requestId, "DK_LEVEL", "Death Knight requires a level 55 or higher leader"));
            return true;
        }

        std::vector<Player*> reserved;
        std::set<ObjectGuid> reservedGuids;
        for (PartySlot const& slot : slots)
        {
            Player* const bot = ReserveBot(leader, slot, reservedGuids);
            if (!bot)
            {
                EmitResult(handler, ErrorResult(requestId, "NO_BOT", "No free same-faction bot is available for one requested class"));
                return true;
            }
            reserved.push_back(bot);
            reservedGuids.insert(bot->GetGUID());
        }

        // The builder owns only bot-only parties. Disbanding first avoids stale
        // membership and preserves any human-led group by rejecting it above.
        if (Group* const oldGroup = leader->GetGroup())
            oldGroup->Disband(true);
        for (Player* bot : reserved)
            if (Group* const oldBotGroup = bot->GetGroup())
                oldBotGroup->RemoveMember(bot->GetGUID());

        Group* group = new Group();
        if (!group->Create(leader))
        {
            delete group;
            EmitResult(handler, ErrorResult(requestId, "GROUP_CREATE", "AzerothCore could not create the party"));
            return true;
        }
        sGroupMgr->AddGroup(group);

        std::ostringstream prepared;
        for (std::size_t index = 0; index < reserved.size(); ++index)
        {
            Player* const bot = reserved[index];
            PrepareBot(bot, leader, slots[index]);
            if (!group->AddMember(bot))
            {
                EmitResult(handler, ErrorResult(requestId, "GROUP_ADD", "A selected bot could not join the party"));
                return true;
            }

            PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
            botAI->SetMaster(leader);
            botAI->ResetStrategies(false);
            SummonAction summon(botAI, "azeroth control party summon");
            if (!summon.Teleport(leader, bot, true))
            {
                bot->TeleportTo(leader->GetMapId(), leader->GetPositionX(), leader->GetPositionY(), leader->GetPositionZ(), leader->GetOrientation());
            }

            if (index)
                prepared << ';';
            prepared << bot->GetName() << ',' << static_cast<uint32>(slots[index].classId) << ','
                     << static_cast<uint32>(slots[index].specId);
        }

        std::ostringstream result;
        result << "AZC_PARTY_RESULT|" << requestId << "|OK|" << leader->GetName() << '|'
               << static_cast<uint32>(leader->GetLevel()) << '|' << reserved.size() << '|' << prepared.str();
        EmitResult(handler, result.str());
        return true;
    }

    static bool HandlePartyAction(ChatHandler* handler, char const* arguments, std::string const& action)
    {
        std::istringstream input(arguments ? arguments : "");
        std::string requestId;
        std::string leaderName;
        input >> requestId >> leaderName;
        if (!IsSafeToken(requestId, 32, true))
            return false;
        if (!IsSafeToken(leaderName, 12))
        {
            EmitResult(handler, ErrorResult(requestId, "BAD_REQUEST", "Invalid leader name"));
            return true;
        }

        Player* const leader = ObjectAccessor::FindPlayerByName(leaderName, true);
        if (!leader || !leader->GetSession() || GET_PLAYERBOT_AI(leader))
        {
            EmitResult(handler, ErrorResult(requestId, "LEADER_OFFLINE", "The selected player is not online"));
            return true;
        }
        Group* const group = leader->GetGroup();
        if (!group)
        {
            EmitResult(handler, ErrorResult(requestId, "NO_PARTY", "The selected player is not in a party"));
            return true;
        }
        if (group->isLFGGroup() || group->isBGGroup() || group->isBFGroup())
        {
            EmitResult(handler, ErrorResult(requestId, "SPECIAL_GROUP", "Dungeon Finder and battleground parties are not modified"));
            return true;
        }
        if (GroupHasOtherHuman(group, leader))
        {
            EmitResult(handler, ErrorResult(requestId, "HUMAN_PARTY", "Party Recovery works only with bot-only parties"));
            return true;
        }

        std::vector<Player*> const bots = ManagedPartyBots(leader);
        if (bots.empty())
        {
            EmitResult(handler, ErrorResult(requestId, "NO_BOTS", "No online bots were found in this party"));
            return true;
        }
        if (action != "disband" && (leader->IsInCombat() || leader->InBattleground() || leader->InBattlegroundQueue() ||
            leader->IsBeingTeleported() || leader->IsInFlight()))
        {
            EmitResult(handler, ErrorResult(requestId, "LEADER_BUSY", "Leave combat, queues, battlegrounds and flight first"));
            return true;
        }

        if (action == "disband")
        {
            for (Player* bot : bots)
            {
                PlayerbotAI* const botAI = GET_PLAYERBOT_AI(bot);
                botAI->SetMaster(nullptr);
                botAI->Reset();
            }
            group->Disband(true);
        }
        else
        {
            for (Player* bot : bots)
            {
                if (action == "prepare" || action == "recover")
                    PrepareExistingBot(bot, leader);
                if (action == "summon" || action == "recover")
                    SummonPartyBot(bot, leader);
            }
        }

        std::ostringstream result;
        result << "AZC_PARTY_RESULT|" << requestId << "|OK|" << action << '|'
               << leader->GetName() << '|' << bots.size();
        EmitResult(handler, result.str());
        return true;
    }

    static bool HandlePartySummon(ChatHandler* handler, char const* arguments)
    {
        return HandlePartyAction(handler, arguments, "summon");
    }

    static bool HandlePartyPrepare(ChatHandler* handler, char const* arguments)
    {
        return HandlePartyAction(handler, arguments, "prepare");
    }

    static bool HandlePartyRecover(ChatHandler* handler, char const* arguments)
    {
        return HandlePartyAction(handler, arguments, "recover");
    }

    static bool HandlePartyDisband(ChatHandler* handler, char const* arguments)
    {
        return HandlePartyAction(handler, arguments, "disband");
    }
};

class AzerothControlLfgFillerScript : public ServerScript
{
public:
    AzerothControlLfgFillerScript()
        : ServerScript("AzerothControlLfgFillerScript", { SERVERHOOK_CAN_PACKET_RECEIVE }) { }

    bool CanPacketReceive(WorldSession* session, WorldPacket const& packet) override
    {
        if (!session || packet.GetOpcode() != CMSG_LFG_JOIN)
            return true;

        Player* const leader = session->GetPlayer();
        if (!leader || GET_PLAYERBOT_AI(leader) || leader->GetGroup() || leader->GetLevel() < 15 ||
            leader->IsInCombat() || leader->InBattleground() || leader->InBattlegroundQueue() ||
            leader->IsBeingTeleported() || leader->IsInFlight())
            return true;

        WorldPacket copy(packet);
        uint32 requestedRoles = 0;
        copy >> requestedRoles;
        requestedRoles &= lfg::PLAYER_ROLE_TANK | lfg::PLAYER_ROLE_HEALER | lfg::PLAYER_ROLE_DAMAGE;
        if (!requestedRoles)
            return true;

        std::vector<PartyRole> roles;
        if (requestedRoles & lfg::PLAYER_ROLE_TANK)
            roles = {PartyRole::Healer, PartyRole::Damage, PartyRole::Damage, PartyRole::Damage};
        else if (requestedRoles & lfg::PLAYER_ROLE_HEALER)
            roles = {PartyRole::Tank, PartyRole::Damage, PartyRole::Damage, PartyRole::Damage};
        else
            roles = {PartyRole::Tank, PartyRole::Healer, PartyRole::Damage, PartyRole::Damage};

        std::vector<Player*> reserved;
        std::vector<PartySlot> slots;
        std::set<ObjectGuid> reservedGuids;
        for (PartyRole role : roles)
        {
            PartySlot slot;
            Player* const bot = ReserveBotForRole(leader, role, reservedGuids, slot);
            if (!bot)
            {
                LOG_WARN("module.azeroth-control", "Instant LFG could not find a complete same-faction party for {}", leader->GetName());
                return true;
            }
            reserved.push_back(bot);
            slots.push_back(slot);
            reservedGuids.insert(bot->GetGUID());
        }

        for (Player* bot : reserved)
            if (Group* const oldBotGroup = bot->GetGroup())
                oldBotGroup->RemoveMember(bot->GetGUID());

        Group* group = new Group();
        if (!group->Create(leader))
        {
            delete group;
            return true;
        }
        sGroupMgr->AddGroup(group);

        for (std::size_t index = 0; index < reserved.size(); ++index)
        {
            PrepareBot(reserved[index], leader, slots[index]);
            if (!group->AddMember(reserved[index]))
            {
                group->Disband(true);
                return true;
            }
        }

        LOG_INFO("module.azeroth-control", "Prepared an instant LFG party for {} at level {}", leader->GetName(), leader->GetLevel());
        ChatHandler(session).SendSysMessage("Azeroth Control prepared a level-matched tank, healer and DPS party for Dungeon Finder.");
        return true;
    }
};

void AddSC_azeroth_control_bridge()
{
    new AzerothControlBridgeCommand();
    new AzerothControlLfgFillerScript();
}

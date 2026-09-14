import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]


class CoAProviderTests(unittest.TestCase):
    def import_server(self, root: Path, module_name: str):
        old_root = os.environ.get("AZEROTH_SERVER_ROOT")
        old_backup = os.environ.get("AZEROTH_CONTROL_BACKUP_ROOT")
        os.environ["AZEROTH_SERVER_ROOT"] = str(root)
        os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = str(root / "backups")
        try:
            spec = importlib.util.spec_from_file_location(module_name, REPOSITORY / "backend/server.py")
            server = importlib.util.module_from_spec(spec)
            assert spec.loader
            spec.loader.exec_module(server)
            return server
        finally:
            if old_root is None:
                os.environ.pop("AZEROTH_SERVER_ROOT", None)
            else:
                os.environ["AZEROTH_SERVER_ROOT"] = old_root
            if old_backup is None:
                os.environ.pop("AZEROTH_CONTROL_BACKUP_ROOT", None)
            else:
                os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = old_backup

    def test_catalog_has_pinned_coa_and_optional_autobalance(self):
        catalog = json.loads((REPOSITORY / "manifests/catalog.json").read_text())
        coa = next(item for item in catalog["providers"] if item["id"] == "azerothcore-coa")
        self.assertRegex(coa["core"]["revision"], r"^[0-9a-f]{40}$")
        self.assertFalse(coa["capabilities"]["bots"])
        autobalance = next(item for item in coa["modules"] if item["id"] == "autobalance")
        self.assertRegex(autobalance["revision"], r"^[0-9a-f]{40}$")
        self.assertTrue(autobalance["default"])

    def test_coa_prefers_ascension_executable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            client = root / "ascension-live"
            client.mkdir()
            (client / "Ascension.exe").touch()
            (client / "Wow.exe").touch()
            (root / "install-selection.json").write_text(json.dumps({
                "provider": "azerothcore-coa",
                "clientPath": str(client),
            }))
            server = self.import_server(root, "coa_client_test_server")
            self.assertEqual(server.client_executable(), client / "Ascension.exe")
            installer = (REPOSITORY / "scripts/install-server.sh").read_text()
            self.assertIn("CLIENT_EXECUTABLE_NAMES=(Ascension.exe ascension.exe", installer)

    def test_managed_database_has_no_host_port_binding(self):
        control = (REPOSITORY / "scripts/server-control-managed").read_text()
        installer = (REPOSITORY / "scripts/install-server.sh").read_text()
        self.assertNotIn("-p 127.0.0.1:3307:3306", control)
        self.assertNotIn("for port in 3307", installer)
        self.assertIn("Checkpoint resumes must still receive fixes", installer)

    def test_coa_mysql_wrapper_preserves_importer_options_first(self):
        wrapper = (REPOSITORY / "scripts/coa-mysql-managed").read_text()
        self.assertIn('exec mysql "$@" -uroot -p"$MYSQL_ROOT_PASSWORD"', wrapper)
        self.assertNotIn('exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$@"', wrapper)

    def test_coa_uses_its_verified_world_baseline_without_newer_world_updates(self):
        control = (REPOSITORY / "scripts/server-control-managed").read_text()
        self.assertIn('updates_enable_databases=3', control)
        self.assertIn('-e "AC_UPDATES_ENABLE_DATABASES=$updates_enable_databases"', control)
        self.assertIn('auth (1) and character (2) updates enabled, but leave world (4)', control)

    def test_coa_uses_upstream_verified_client_endpoint_fix_with_backup(self):
        installer = (REPOSITORY / "scripts/install-server.sh").read_text()
        self.assertIn('apps/client-compat/patch_world_endpoint.py', installer)
        self.assertIn('Extensions.dll.azeroth-control-backup', installer)
        self.assertIn('f7b713095aab17a1e376f487290d4b7c4c18931635e4d91136d76db2592be8fa', installer)
        self.assertIn('9791801053f828d1ccdab1a4c17e64852d3ebe0fa708b91fa3674d0805d15bc8', installer)
        self.assertIn('python3 "$ENDPOINT_PATCHER" --input "$EXTENSIONS_DLL" --output "$EXTENSIONS_CANDIDATE"', installer)

    def test_coa_extracts_matching_client_dbcs_before_worldserver_starts(self):
        installer = (REPOSITORY / "scripts/install-server.sh").read_text()
        control = (REPOSITORY / "scripts/server-control-managed").read_text()
        self.assertIn('--target tools -t "$SHARED_TOOLS_IMAGE"', installer)
        self.assertIn('coa-client-dbc-v2-installed', installer)
        self.assertIn('map_extractor -e 2 -i /client -o /output', control)
        self.assertIn('test -s /output/dbc/Spell.dbc', control)
        self.assertIn('Ascension/Appearances.dbc', control)
        self.assertIn('cp -Rf /input/dbc/. /azerothcore/env/dist/data/dbc/', control)
        self.assertIn('continuing without collections', control)
        self.assertIn("AscensionCompat.DbcDirectory '/azerothcore/env/dist/data/dbc/Ascension'", control.replace('"', ''))
        self.assertIn('local coa_client_dbc_ready=1', control)

    def test_existing_coa_server_has_a_client_data_migration_action(self):
        controller = (REPOSITORY / "native/controller.cpp").read_text()
        qml = (REPOSITORY / "native/qml/Main.qml").read_text()
        self.assertIn("void Controller::applyCoaClientDataFix()", controller)
        self.assertIn('text: "Apply CoA client-data fix"', qml)

    def test_coa_xp_rate_writes_all_azerothcore_rate_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "runtime/etc/worldserver.conf"
            config.parent.mkdir(parents=True)
            config.write_text(
                "Rate.XP.Kill = 1\nRate.XP.Quest = 1\nRate.XP.Explore = 1\n"
                "Respawn.DynamicRateCreature = 1\nRate.Drop.Item.Normal = 1\n"
            )
            modules = root / "runtime/etc/modules"
            modules.mkdir()
            (modules / "AutoBalance.conf").write_text("AutoBalance.Enable.Global=1\n")
            (modules / "mod_ascension_compat.conf").write_text("AscensionCompat.LevelScaling = 0\n")
            (root / "install-selection.json").write_text(json.dumps({"provider": "azerothcore-coa"}))
            old_root = os.environ.get("AZEROTH_SERVER_ROOT")
            old_backup = os.environ.get("AZEROTH_CONTROL_BACKUP_ROOT")
            os.environ["AZEROTH_SERVER_ROOT"] = str(root)
            os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = str(root / "backups")
            try:
                spec = importlib.util.spec_from_file_location("coa_test_server", REPOSITORY / "backend/server.py")
                server = importlib.util.module_from_spec(spec)
                assert spec.loader
                spec.loader.exec_module(server)
                server.save_settings("coa", {"xpRate": 5})
            finally:
                if old_root is None:
                    os.environ.pop("AZEROTH_SERVER_ROOT", None)
                else:
                    os.environ["AZEROTH_SERVER_ROOT"] = old_root
                if old_backup is None:
                    os.environ.pop("AZEROTH_CONTROL_BACKUP_ROOT", None)
                else:
                    os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = old_backup
            text = config.read_text()
            self.assertIn("Rate.XP.Kill = 5", text)
            self.assertIn("Rate.XP.Quest = 5", text)
            self.assertIn("Rate.XP.Explore = 5", text)

    def test_disabling_autobalance_restores_coa_level_scaling(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            modules = root / "runtime/etc/modules"
            modules.mkdir(parents=True)
            (modules / "AutoBalance.conf").write_text("AutoBalance.Enable.Global=1\n")
            ascension = modules / "mod_ascension_compat.conf"
            ascension.write_text("AscensionCompat.LevelScaling = 0\n")
            (root / "install-selection.json").write_text(json.dumps({"provider": "azerothcore-coa"}))
            old_root = os.environ.get("AZEROTH_SERVER_ROOT")
            old_backup = os.environ.get("AZEROTH_CONTROL_BACKUP_ROOT")
            os.environ["AZEROTH_SERVER_ROOT"] = str(root)
            os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = str(root / "backups")
            try:
                spec = importlib.util.spec_from_file_location("coa_balance_test_server", REPOSITORY / "backend/server.py")
                server = importlib.util.module_from_spec(spec)
                assert spec.loader
                spec.loader.exec_module(server)
                server.save_settings("coa", {"autoBalance": False})
            finally:
                if old_root is None:
                    os.environ.pop("AZEROTH_SERVER_ROOT", None)
                else:
                    os.environ["AZEROTH_SERVER_ROOT"] = old_root
                if old_backup is None:
                    os.environ.pop("AZEROTH_CONTROL_BACKUP_ROOT", None)
                else:
                    os.environ["AZEROTH_CONTROL_BACKUP_ROOT"] = old_backup
            self.assertIn("AutoBalance.Enable.Global=0", (modules / "AutoBalance.conf").read_text())
            self.assertIn("AscensionCompat.LevelScaling = 1", ascension.read_text())


if __name__ == "__main__":
    unittest.main()

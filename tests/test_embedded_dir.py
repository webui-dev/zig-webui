"""Exercise the public build API using a real, isolated downstream project.

Run with: python3 -m unittest discover -s tests -v
Requires Zig on PATH; no third-party Python dependencies.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class EmbeddedDirIntegrationTest(unittest.TestCase):
    def test_downstream_embedding_and_incremental_rebuilds(self):
        # Stay on the repository's volume so relative package paths work on Windows.
        with tempfile.TemporaryDirectory(prefix=".embed-test-", dir=REPO) as temporary:
            root = Path(temporary).resolve()
            project = root / "consumer"
            assets = project / "assets"
            assets.mkdir(parents=True)
            (project / "empty").mkdir()
            (project / "other").mkdir()
            (project / "other/index.html").write_bytes(b"other directory")
            files = {
                "index.html": b"<h1>embedded</h1>",
                "nested/data.bin": bytes(range(256)),
                "empty.txt": b"",
                "embedded_assets.zig": b"resource, not generated Zig source",
                "space name.txt": b"spaces",
                "中文.txt": "内容".encode(),
            }
            if os.name != "nt":
                files['quote"name.txt'] = b"quote"
                files["back\\slash.txt"] = b"backslash"
            for name, data in files.items():
                path = assets / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            dependency = Path(os.path.relpath(REPO, project)).as_posix()
            (project / "build.zig.zon").write_text(
                '.{ .name = .myapp, .version = "0.1.0", '
                '.fingerprint = 0x8798022a7d1f3aaf, '
                '.minimum_zig_version = "0.16.0", '
                '.dependencies = .{ .zig_webui = .{ .path = "'
                + dependency
                + '" } }, .paths = .{""} }\n',
                encoding="utf-8",
            )
            (project / "build.zig").write_text(BUILD, encoding="utf-8")
            (project / "main.zig").write_text(MAIN, encoding="utf-8")
            executable = root / "out/bin" / (
                "embed-check.exe" if os.name == "nt" else "embed-check"
            )

            def build():
                result = subprocess.run(
                    ["zig", "build", "--build-file", str(project / "build.zig"),
                     "--prefix", str(root / "out")],
                    cwd=root, capture_output=True, timeout=180,
                )
                self.assertEqual(result.returncode, 0,
                                 result.stderr.decode(errors="replace"))

            def check(binary=executable):
                result = subprocess.run(
                    [str(binary)], cwd=root, capture_output=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0,
                                 result.stderr.decode(errors="replace"))
                expected = b"".join(
                    name.encode() + b"\0" + files[name].hex().encode() + b"\n"
                    for name in sorted(files, key=lambda name: name.encode())
                )
                self.assertEqual(result.stderr, expected)

            with self.subTest("initial build outside consumer root"):
                build()
                check()
            with self.subTest("unchanged rebuild"):
                build()
                check()
            with self.subTest("content-only edit invalidates cache"):
                files["index.html"] = b"updated resource without Zig source changes"
                (assets / "index.html").write_bytes(files["index.html"])
                build()
                check()
            with self.subTest("new file discovered"):
                files["nested/added.txt"] = b"added"
                (assets / "nested/added.txt").write_bytes(files["nested/added.txt"])
                build()
                check()
            with self.subTest("deleted and renamed files update keys"):
                del files["empty.txt"]
                (assets / "empty.txt").unlink()
                files["renamed.txt"] = files.pop("nested/added.txt")
                (assets / "nested/added.txt").rename(assets / "renamed.txt")
                build()
                check()
            with self.subTest("standalone execution without source project"):
                standalone = root / executable.name
                shutil.copy2(executable, standalone)
                shutil.rmtree(project)
                check(standalone)


BUILD = '''const std = @import("std");
const webui = @import("zig_webui");
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("zig_webui", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "embed-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("webui", dep.module("webui"));
    try webui.addEmbeddedDir(b, exe.root_module, .{ .path = "assets" });
    try webui.addEmbeddedDir(b, exe.root_module, .{
        .path = "empty", .import_name = "empty_assets",
    });
    try webui.addEmbeddedDir(b, exe.root_module, .{
        .path = "other", .import_name = "other_assets",
    });
    b.installArtifact(exe);
}
'''

MAIN = r'''const std = @import("std");
const webui = @import("webui");
const Assets = webui.EmbeddedFS(@import("embedded_assets"));
const Empty = webui.EmbeddedFS(@import("empty_assets"));
const Other = webui.EmbeddedFS(@import("other_assets"));
pub fn main() !void {
    try std.testing.expectEqual(@as(usize, 0), Empty.list().len);
    try std.testing.expect(Empty.get("index.html") == null);
    try std.testing.expectEqualStrings("other directory", Other.get("index.html").?);
    for (Assets.list()) |path| {
        std.debug.print("{s}\x00{x}\n", .{ path, Assets.get(path).? });
    }
}
'''


if __name__ == "__main__":
    unittest.main()

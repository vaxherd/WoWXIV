#!/usr/bin/python
#
# Transfer addon files between the host PC and the in-game environment.
#
# Usage:
#
# overlay-ctl.py install TARGET-PATH
#     Installs the addon to the given TARGET-PATH. typically
#     "Interface/AddOns/WoWXIV" under the WoW game directory, with the
#     addon files (other than non-text data files) available in the
#     in-game development environment.
#
# overlay-ctl.py pull SAVEDVARIABLES-PATH
#     Reads data updated in-game from the given SavedVariables file,
#     typically "WTF/Account/...#1/SavedVariables/WoWXIV.lua" under the
#     WoW game directory, and writes the updated data into the current
#     directory tree.

import os
import re
import stat
import sys


def do_install(src, dest):
    """Install the addon from |src| to |dest|.

    |src| should be the root path of the addon source tree (the parent
    directory of this script's directory).

    |dest| should be the path of the target directory.  If the directory
    does not exist, it (but not any parents) will be created.  If the
    directory already exists, colliding files will be replaced, but any
    files which are not present in the source tree will not be removed.
    """
    with open(os.path.join(src, "WoWXIV.toc"), "r") as f:
        toc_in = f.readlines()
    found_files = False
    scripts = []
    toc_out = []
    for line in toc_in:
        if not found_files:
            if re.match(r"^\s*[^#\s]", line):
                found_files = True
                toc_out.append("dev/loader.lua\n")
            else:
                toc_out.append(line)
        if found_files:
            m = re.match(r"^\s*([^#\s]+)", line)
            if m:
                name = m.group(1)
                name = re.sub(r"[/\\]+", "/", name)
                if name.endswith(".lua"):
                    scripts.append(name)
                else:
                    toc_out.append(name+"\n")
    # end for

    fs_tree = {}    # Files to store in the dev filesystem
    copy_list = []  # Files to copy directly to the target path
    def scan(subdir, tree_out):
        for entry in os.scandir(os.path.join(src, subdir or ".")):
            name = entry.name
            path = os.path.join(subdir, name) if subdir else name
            if entry.is_dir():
                if name != ".git":
                    tree_out[name] = {}
                    scan(path, tree_out[name])
            else:
                m = re.search(r"\.([^./]+)$", name)
                ext = m.group(1) if m else ""
                if ext not in ("png", "xcf", "ttf"):
                    with open(os.path.join(src, path), "rb") as f:
                        tree_out[name] = f.read()
                if not subdir.startswith("tools") and ext not in ("toc", "lua"):
                    copy_list.append(path)
    # end def
    scan("", fs_tree)

    charmap = [chr(i) if 32<=i<=126 else f"\\{i:03d}" for i in range(256)]
    charmap[9] = "\\t"
    charmap[10] = "\\n"
    charmap[34] = '\\"'
    charmap[92] = '\\\\'
    def write_tree(tree, out, indent=""):
        for name in sorted(tree.keys()):
            object = tree[name]
            if isinstance(object, dict):
                out.append(f'{indent}["{name}"]' + " = {\n")
                write_tree(object, out, indent+"    ")
                out.append(indent+"},\n")
            else:
                assert isinstance(object, bytes)
                data = "".join(charmap[c] for c in object)
                out.append(f'{indent}["{name}"] = "{data}",\n')
    # end def
    loader_out = []
    with open(os.path.join(src, "dev/loader.lua"), "r") as f:
        for line in f.readlines():
            if line.startswith("--@LOAD_ORDER@--"):
                for name in scripts:
                    loader_out.append(f'"{name}",\n')
            elif line.startswith("--@FS_DATA@--"):
                write_tree(fs_tree, loader_out)
            else:
                loader_out.append(line)

    try:
        os.mkdir(dest)
    except FileExistsError:
        pass
    with open(os.path.join(dest, "WoWXIV.toc"), "w") as f:
        f.writelines(toc_out)
    try:
        os.mkdir(os.path.join(dest, "dev"))
    except FileExistsError:
        pass
    with open(os.path.join(dest, "dev/loader.lua"), "w") as f:
        f.writelines(loader_out)
    for path in copy_list:
        dir, name = os.path.split(path)
        if dir:
            try:
                os.mkdir(os.path.join(dest, dir))
            except FileExistsError:
                pass
        with open(os.path.join(src, path), "rb") as f_in:
            with open(os.path.join(dest, path), "wb") as f_out:
                f_out.write(f_in.read())
# end def

def do_pull(src, dest):
    """Extract changes from |src| to |dest|.

    |src| should be the WoW SavedVariables file holding the overlay
    table for the addon data filesystem.

    |dest| should be the root path of the addon source tree (the parent
    directory of this script's directory).
    """
    with open(src, "r") as f:
        lines = f.readlines()
    fs = {}
    ROOT_INODE = 1
    inode = None
    dir = None
    for line in lines:
        line = re.sub(r"\r?\n$", "", line)
        if line == "WoWXIV_initfs_overlay = {":
            inode = ROOT_INODE
        elif not inode:
            continue
        elif line == "}":
            assert dir is None
            break
        elif line == "},":
            assert dir is not None
            dir = None
            inode += 1
        else:
            m = re.match(r'(?:\[(\d+|"(?:\\"|[^"])*")\] = )?(.+)', line)
            assert m
            k, v = m.groups()
            if v == "{":
                assert not dir
                inode = int(k) if k else inode
                fs[inode] = {}
                dir = fs[inode]
            elif dir is None:
                assert v.startswith('"')
                assert v.endswith('",')
                escapes = {"n": "\n", "r": "\r", "t": "\t"}
                v = re.sub(
                    r"\\(.)", lambda m: escapes.get(m.group(1), m.group(1)),
                    v[1:-2])
                inode = int(k) if k else inode
                fs[inode] = v
                inode += 1
            else:
                assert k.startswith('"')
                assert k.endswith('"')
                assert v.endswith(',')
                dir[k[1:-1]] = int(v[0:-1])
    if not fs:
        sys.stderr.write("*** No overlay data found\n")
        sys.exit(1)
    assert(isinstance(fs[ROOT_INODE], dict))

    def traverse(dir, base_path):
        found_any = False
        for name, inode in dir.items():
            path = os.path.join(base_path, name)
            o = fs[inode]
            if isinstance(o, dict):
                try:
                    os.mkdir(os.path.join(dest, path))
                except FileExistsError:
                    pass
                if traverse(o, path):
                    found_any = True
            else:
                found_any = True
                print(path)
                with open(os.path.join(dest, path), "w") as f:
                    f.write(o)
        return found_any
    # end def
    if not traverse(fs[ROOT_INODE], ""):
        print("(no changes found)")
# end def


def main(argv):
    """Program entry point."""
    command = argv[1] if len(argv) > 1 else None
    path = argv[2] if len(argv) > 2 else None
    if (command != "install" and command != "pull") or path is None:
        sys.stderr.write(f"Usage: {argv[0]} install TARGET-PATH\n" +
                         f"       {argv[0]} pull SAVEDVARIABLES-PATH\n")
        sys.exit(2)
    root = os.path.dirname(os.path.dirname(os.path.abspath(argv[0])))
    assert os.stat(os.path.join(root, "tools/overlay-ctl.py"))
    if command == "install":
        do_install(root, path)
    else:
        assert command == "pull"
        do_pull(path, root)

if __name__ == "__main__":
    main(sys.argv)

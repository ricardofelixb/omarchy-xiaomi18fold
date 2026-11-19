#!/usr/bin/python3 -I
"""Hand folders an older root-run install left owned by root back to the user.

usage: fix-user-dirs.py HOME UID GID NAME... (NAME... is the chain of folders below HOME)

Each folder is opened relative to the one before it, without following links, and changed through
its file descriptor. A link planted by the user (for example ~/.config -> /etc) stops the walk, so
nothing outside HOME is ever touched. A missing folder also stops it.
"""
import os
import sys

FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def repair(home, uid, gid, names, stale=0):
    fd = os.open(home, FLAGS)
    try:
        for name in names:
            try:
                child = os.open(name, FLAGS, dir_fd=fd)
            except OSError:
                break
            os.close(fd)
            fd = child
            if os.fstat(fd).st_uid == stale:
                os.fchown(fd, uid, gid)
    finally:
        os.close(fd)


if __name__ == "__main__":
    repair(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:])

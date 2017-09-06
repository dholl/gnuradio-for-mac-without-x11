#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim:set ft=python ai ts=8 et sw=4 sts=4 nowrap:
# The above line sets vim to set tab stops at 4 columns, and fill them with spaces instead of tab characters.

"""
path_tools.py - A few tools for path manipulation
"""

import os as _os
import stat as _stat
import warnings as _warnings

# Module-wide assumptions:
assert len(_os.sep) == 1
assert '..'==u'..'
assert '.'==u'.'

def samelfile(path1, path2):
    # Like os.path.samefile but uses lstat, so I don't dereference a symlink
    # that was pointed at from another symlink.
    return _os.path.samestat(_os.lstat(path1), _os.lstat(path2))

def safe_normpath(path, remove_dotdots=True, stat_test=True):
    """
    safe_normpath - similar to os.path.normpath, but tries to be safe with symbolic links

    Specifically:
        Guarantee that lstat points to the same file.
        If remove_dotdots==True, then:
            Only collapse 'a/blah/../b' into 'a/b' when 'blah' is a directory, not a symbolic link to a directory.
            Collapse '/a/b/../../../../..' to '/' with a warning emitted.
        If path ends '.' then the output will include the ending '.'.  Otherwise, /b/./c/d/. -> /b/c/d/.
            (Because if /b/c/d is a symlink, then /b/c/d/. is the directory that it points too and not the symlink.)

        If remove_dotdots==False, then skip all lstat checks, but don't collapse any '..'
    """

    # We only deal with real paths.  They may be relative or absolute, but they
    # must refer to something that exists.  (If you want purely fictional
    # paths, then use os.path.normpath.)
    if stat_test:
        st1 = _os.lstat(path)

    path_list = path.split(_os.sep)
    assert isinstance(path_list, list)
    # Assume unix paths.
    # Remove all empty '' and '.' from the middle of the list, because these are a//b or a/./b
    if len(path_list)>2:
        path_list = path_list[:1] + filter(lambda p: p not in {'', '.'}, path_list[1:-1]) + path_list[-1:]
    #for p in path_list:
    if not remove_dotdots:
        # Don't collapse ANY '..' elements:
        new_path_list = path_list
    else:
        new_path_list = []
        # Only remove '..' elements if they refer to a real directory:
        for ndx in range(len(path_list)):
            if stat_test:
                if not _os.path.samestat(st1, _os.lstat(_os.sep.join(new_path_list+path_list[ndx:]))):
                    raise RuntimeError('Failed sanity check:  While simplifying {!r}, os.path.samestat fails for intermediate result {!r}.\n\tDebug:\n\t\tnew_path_list={!r}\n\t\tpath_list[{}:]={!r}\n\t\ttested path={!r}\n'.format(new_path_list, ndx, path_list[ndx:], _os.sep.join(new_path_list+path_list[ndx:])))

            current_name = path_list[ndx]

            if current_name!='..':
                new_path_list.append(current_name) # append the current entry from path_list
                continue

            # So current_name=='..', can we safely remove it?

            if samelfile(_os.sep.join(new_path_list), _os.sep.join(new_path_list+['..'])):
                # We must be at root /, since / == /..
                _warnings.warn('Path {!r} is trying to access up beyond /', RuntimeWarning)

            if not new_path_list:
                new_path_list.append(current_name) # append the current entry from path_list
                continue

            if new_path_list[-1] == '..':
                new_path_list.append(current_name) # append the current entry from path_list
                continue

            if new_path_list == ['']:
                # Drop the .. since /.. -> /
                continue

            if _stat.S_ISDIR(_os.lstat(_os.sep.join(new_path_list)).st_mode): # _os.path.isdir can get fooled.  I want lstat here.
                # Yep, current_name=='..' and new_path_list refers to a directory, so remove the
                # last entry on new_path_list and don't store current_name:
                del new_path_list[-1]
            else:
                new_path_list.append(current_name) # append the current entry from path_list

    new_path = _os.sep.join(new_path_list)
    if stat_test:
        if not _os.path.samestat(st1, _os.lstat(new_path)):
            raise RuntimeError('Failed sanity check:  Simplified {!r} into {!r} but os.path.samestat returns False'.format(path, new_path))
    return new_path

def norm_split_path(path):
    """
    '../..//some/.///path//' -> ['..', '..', 'some', 'path']
    '////../..//some/.///path//' -> ['', 'some', 'path']
    """
    return safe_normpath(path, remove_dotdots=False, stat_test=False).split(_os.sep)

def path_is_subpath(basepath, filepath):
    norm_basepath = norm_split_path(basepath)
    norm_filepath = norm_split_path(filepath)
    return norm_basepath==norm_filepath[:len(norm_basepath)]


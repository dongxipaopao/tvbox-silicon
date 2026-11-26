# ipa

Built installers are not stored in this public repository. They are unsigned, 150 MB or more, and GitHub does not accept files that large in git.

Where they are:

- Each CI build (workflows `build-ios` and `build-tvos`) writes the installer into this folder in the build checkout as `ipa/Yingxia-<version>-b<build>-<commit>-<platform>-unsigned.ipa` and uploads it as the `ipa-named` artifact of that run.
- The same file is copied to the owner's private repository as a private release asset with the same name.
- `*.ipa` is git-ignored here, so a binary cannot be committed by accident.

The installers are unsigned: sign them with your own certificate before installing.

Use this script to export/import user data from a browser including bookmarks, saved passwords, etc.

**This script is not needed if user uses a signed-in cloud account for their preferred browser**

  1. Run Export-BrowserProfiles.ps1 on current user device.
  2. Copy BrowserExport folder from designated user's User folder, to an external drive.
  3. Have user log in on new device to populate their User folder.
  4. Move BrowserExport folder from external drive into user's designated User folder.
  5. Run Import-BrowserProfiles.ps1 on new user device
  6. Once import is finished, check preferred browser for bookmarks, saved passwords, etc.

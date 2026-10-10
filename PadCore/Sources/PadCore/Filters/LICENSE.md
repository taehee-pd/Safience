# The filter lists

`easylist.txt` and `easyprivacy.txt` are EasyList and EasyPrivacy, by the EasyList authors (https://easylist.to/), copied unchanged from https://easylist.to/easylist/ on the date in each file's `! Last modified:` line.

The EasyList authors dual-license them under the GNU General Public License version 3 or later, and under Creative Commons Attribution-ShareAlike 3.0 Unported or later (https://easylist.to/pages/licence.html). Safience uses them under Creative Commons Attribution-ShareAlike (https://creativecommons.org/licenses/by-sa/4.0/).

The app turns them into WebKit's content-blocking rules on the device (`ContentBlocking.swift`); those rules are an adaptation of the lists and are under the same licence. Safience's own code is not part of the lists and is not covered by it.

The app downloads newer copies from https://easylist.to/easylist/ no more than once every four days, as the lists' `! Expires:` line asks.

import XMonad
import XMonad.Config.Desktop
import XMonad.Util.Paste
import XMonad.Hooks.DynamicLog
import XMonad.Util.EZConfig
import XMonad.Hooks.EwmhDesktops
import Graphics.X11.ExtraTypes.XF86
import qualified XMonad.StackSet as W
import XMonad.Hooks.SetWMName

main = xmonad . ewmhFullscreen . ewmh =<< xmobar myConfig

myConfig = def
  { terminal = myTerminal
  , borderWidth = myBorderWidth
  , modMask = mod4Mask
  , startupHook = setWMName "LG3D" -- Abevjava only (gray windows)
  }
  `additionalKeysP`
  [ ("M4-<F10>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("M4-<F11>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("M4-<F9>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle && notify-send 'Audio' \"$(pactl get-sink-mute @DEFAULT_SINK@)\"")
    , ("<XF86AudioLowerVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("<XF86AudioRaiseVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("<XF86AudioMute>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle && notify-send 'Audio' \"$(pactl get-sink-mute @DEFAULT_SINK@)\"")
    , ("M4-<F3>", spawn "/home/sashee/dotfiles/functions/manage-brightness.sh dec && notify-send 'Brightness' \"$(echo \"$(/home/sashee/dotfiles/functions/manage-brightness.sh)\")\"")
    , ("M4-<F4>", spawn "/home/sashee/dotfiles/functions/manage-brightness.sh inc && notify-send 'Brightness' \"$(echo \"$(/home/sashee/dotfiles/functions/manage-brightness.sh)\")\"")
    , ("<XF86MonBrightnessDown>", spawn "xbacklight -dec 1 && notify-send 'Brightness' $(xbacklight -get)")
    , ("<XF86MonBrightnessUp>", spawn "xbacklight -inc 1 && notify-send 'Brightness' $(xbacklight -get)")
    , ("C-M4-<XF86PowerOff>", spawn "systemctl poweroff")
    , ("M1-<Tab>", windows W.focusDown)
    , ("M4-S-o", spawn "firejail chromium")
    , ("M4-S-i", spawn "firejail chromium --incognito")
    , ("M4-S-;", spawn "flameshot gui")
    , ("M4-S-l", spawn "killall ssh")
    , ("M4-S-u", spawn "xscreensaver-command -lock")
    , ("M4-S-m", spawn "if [[ \"$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)\" == \"schedutil\" ]]; then sudo -n cpupower frequency-set -g powersave; else sudo -n cpupower frequency-set -g schedutil; fi")
    , ("M4-S-,", spawn "/home/sashee/dotfiles/functions/manage-brightness.sh turn_nightlight")
  ]

myTerminal = "alacritty"
myBorderWidth = 4

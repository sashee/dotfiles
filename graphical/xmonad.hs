import XMonad
import XMonad.Config.Desktop
import XMonad.Util.Paste
import XMonad.Hooks.DynamicLog
import XMonad.Util.EZConfig
import XMonad.Hooks.EwmhDesktops
import Graphics.X11.ExtraTypes.XF86
import qualified XMonad.StackSet as W

main = xmonad . ewmhFullscreen . ewmh =<< xmobar myConfig

myConfig = def
  { terminal = myTerminal
  , borderWidth = myBorderWidth
  , modMask = mod4Mask
  }
  `additionalKeysP`
  [ ("M4-<F9>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("M4-<F10>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("M4-<F8>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle && notify-send 'Audio' \"$(pactl get-sink-mute @DEFAULT_SINK@)\"")
    , ("<XF86AudioLowerVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("<XF86AudioRaiseVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +5% && notify-send 'Audio' $(~/dotfiles/functions/get-volume.sh)")
    , ("<XF86AudioMute>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle && notify-send 'Audio' \"$(pactl get-sink-mute @DEFAULT_SINK@)\"")
    , ("M4-<F6>", spawn "xbacklight -dec 1% && notify-send 'Brightness' $(xbacklight)")
    , ("M4-<F7>", spawn "xbacklight -inc 1% && notify-send 'Brightness' $(xbacklight)")
    , ("C-M4-<XF86PowerOff>", spawn "systemctl poweroff")
    , ("M1-<Tab>", windows W.focusDown)
    , ("M4-S-o", spawn "chromium")
    , ("M4-S-i", spawn "chromium --incognito")
    , ("M4-S-;", spawn "flameshot gui")
  ]

myTerminal = "alacritty"
myBorderWidth = 4

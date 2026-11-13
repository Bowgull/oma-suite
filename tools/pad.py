"""pad.py: a pretend Xbox controller for testing WoW on the Shadow, where no real pad is plugged in.

Uses the ViGEmBus driver that Shadow's own controller streaming already installed (nothing is installed by this
script) and the vgamepad library files unpacked to C:\\Omashu\\tools\\padlib (its bundled driver setup removed).

Usage:  python -I pad.py step step ...
  wait:2.5            wait seconds
  btn:DPAD_UP         tap a pad button (A, B, X, Y, LB, RB, BACK, START, LS, RS, DPAD_UP/DOWN/LEFT/RIGHT)
  rt / lt             tap a trigger
  rstick:1:0:1.5      hold the right stick at x, y (-1..1) for seconds, then centre it
  lstick:0:1:1.0      same for the left stick
  key:F11             Ctrl+Shift+F11 on the keyboard (WoW must be in front)
  front               bring the WoW window to the front
The pad exists only while the script runs; it disappears when the script ends.
"""
import ctypes, sys, time
from ctypes import wintypes

sys.path.insert(0, r'C:\Omashu\tools\padlib')
import vgamepad as vg

user32 = ctypes.WinDLL('user32', use_last_error=True)
ULONG_PTR = ctypes.c_size_t


class KI(ctypes.Structure):
    _fields_ = [('wVk', wintypes.WORD), ('wScan', wintypes.WORD), ('dwFlags', wintypes.DWORD),
                ('time', wintypes.DWORD), ('dwExtraInfo', ULONG_PTR)]


class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [('ki', KI), ('pad', ctypes.c_byte * 32)]
    _anonymous_ = ('u',)
    _fields_ = [('type', wintypes.DWORD), ('u', _U)]


def keys(seq):
    arr = (INPUT * len(seq))()
    for i, (vk, sc, up) in enumerate(seq):
        arr[i].type = 1
        arr[i].ki = KI(vk, sc, 2 if up else 0, 0, 0)
    return user32.SendInput(len(seq), arr, ctypes.sizeof(INPUT)) == len(seq)


FKEYS = {'F5': (0x74, 0x3F), 'F6': (0x75, 0x40), 'F7': (0x76, 0x41), 'F8': (0x77, 0x42), 'F9': (0x78, 0x43),
         'F10': (0x79, 0x44), 'F11': (0x7A, 0x57), 'F12': (0x7B, 0x58), 'F1': (0x70, 0x3B), 'F2': (0x71, 0x3C),
         'F3': (0x72, 0x3D), 'F4': (0x73, 0x3E)}


def chord(name):
    vk, sc = FKEYS[name]
    return keys([(0x11, 0x1D, 0), (0x10, 0x2A, 0), (vk, sc, 0), (vk, sc, 1), (0x10, 0x2A, 1), (0x11, 0x1D, 1)])


def front():
    h = user32.FindWindowW(None, 'World of Warcraft')
    if not h:
        return False
    user32.keybd_event(0x12, 0, 0, 0)
    user32.SetForegroundWindow(h)
    user32.keybd_event(0x12, 0, 2, 0)
    time.sleep(0.4)
    return user32.GetForegroundWindow() == h


B = vg.XUSB_BUTTON
BUTTONS = {'A': B.XUSB_GAMEPAD_A, 'B': B.XUSB_GAMEPAD_B, 'X': B.XUSB_GAMEPAD_X, 'Y': B.XUSB_GAMEPAD_Y,
           'LB': B.XUSB_GAMEPAD_LEFT_SHOULDER, 'RB': B.XUSB_GAMEPAD_RIGHT_SHOULDER, 'BACK': B.XUSB_GAMEPAD_BACK,
           'START': B.XUSB_GAMEPAD_START, 'LS': B.XUSB_GAMEPAD_LEFT_THUMB, 'RS': B.XUSB_GAMEPAD_RIGHT_THUMB,
           'DPAD_UP': B.XUSB_GAMEPAD_DPAD_UP, 'DPAD_DOWN': B.XUSB_GAMEPAD_DPAD_DOWN,
           'DPAD_LEFT': B.XUSB_GAMEPAD_DPAD_LEFT, 'DPAD_RIGHT': B.XUSB_GAMEPAD_DPAD_RIGHT}


def main(steps):
    pad = vg.VX360Gamepad()
    pad.update()
    print('pad on', flush=True)
    for s in steps:
        p = s.split(':')
        if p[0] == 'wait':
            time.sleep(float(p[1]))
        elif p[0] == 'btn':
            pad.press_button(button=BUTTONS[p[1]]); pad.update(); time.sleep(0.12)
            pad.release_button(button=BUTTONS[p[1]]); pad.update(); time.sleep(0.2)
        elif p[0] in ('rt', 'lt'):
            (pad.right_trigger_float if p[0] == 'rt' else pad.left_trigger_float)(value_float=1.0); pad.update(); time.sleep(0.12)
            (pad.right_trigger_float if p[0] == 'rt' else pad.left_trigger_float)(value_float=0.0); pad.update(); time.sleep(0.2)
        elif p[0] in ('rstick', 'lstick'):
            f = pad.right_joystick_float if p[0] == 'rstick' else pad.left_joystick_float
            f(x_value_float=float(p[1]), y_value_float=float(p[2])); pad.update(); time.sleep(float(p[3]))
            f(x_value_float=0.0, y_value_float=0.0); pad.update(); time.sleep(0.2)
        elif p[0] == 'key':
            print('key', p[1], 'front', front(), 'sent', chord(p[1]), flush=True)
        elif p[0] == 'front':
            print('front', front(), flush=True)
        print('done', s, flush=True)
    del pad
    print('pad off', flush=True)


if __name__ == '__main__':
    main(sys.argv[1:])

import serial
import time
class WDC_talker:
    def __init__(self, port='COM4', b=1200, parity=serial.PARITY_NONE, size=serial.EIGHTBITS,
                 stops=serial.STOPBITS_ONE, to=3.0):
        try:
            self.ser = serial.Serial(port=port, baudrate=b, parity=parity,
                            bytesize=size, stopbits=stops, timeout=to)
            self.open=True
        except:
            print("Error opening port")
            self.open = False

    def _get_attention(self, tries=10):
        synced = False
        ok = False
        while not synced and tries > 0:
            tries -= 1
            self.ser.write(b'\x55')
            self.ser.write(b'\xAA')
            try:
                a = self.ser.read(1)
                if a == b'\xCC':
                    print(a)
                    synced = True
                    ok = True
                else:
                    print("!")
            except:
                print("Timeout!")
                pass
        return ok

    def _send_command(self, cmd, tries=10):
        assert type(cmd) is bytes
        if self._get_attention(tries) is True:
            print("Ready to insert command byte!")
            self.ser.write(cmd)
            print("CMD sent")
        else:
            print("Could not gain attention of controller board")

    def _read(self):
        self.ser.write(b'\xF0')
        self.ser.write(b'\xFF')
        self.ser.write(b'\x00')

        self.ser.write(b'\x20')
        self.ser.write(b'\x00')
        time.sleep(2.0)
        m = self.ser.read(32)
        print(m, len(m))

    def read(self, sa, ea):
        assert type(sa) is int
        assert type(ea) is int
        assert ea > sa
        length = ea - sa + 1
        print("len=", length)

        dl = (length & 0xFF).to_bytes(1)
        dh = ((length >> 8) & 0xFF).to_bytes(1)
        sab = ((sa >> 16) & 0xFF).to_bytes(1)
        sah = ((sa >> 8) & 0xFF).to_bytes(1)
        sal = (sa & 0xFF).to_bytes(1)

        print(sab, sah, sal)
        print(dh, dl)
        self._send_command(b'\x03')
        self.ser.write(sal)
        self.ser.write(sah)
        self.ser.write(sab)

        self.ser.write(dl)
        self.ser.write(dh)

        m = self.ser.read(length)
        print(m, len(m))
        return


if __name__ == "__main__":

    toytalk = WDC_talker('COM4', 1200, serial.PARITY_NONE, serial.EIGHTBITS, serial.STOPBITS_ONE, 3.0)
    print(toytalk)
    toytalk._send_command(b'\x03', 10)
    toytalk._read()
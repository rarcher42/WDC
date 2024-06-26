import serial
import random
import time
class WDC_tester:
    def __init__(self, port='COM17', b=1200, parity=serial.PARITY_NONE, size=serial.EIGHTBITS,
                 stops=serial.STOPBITS_ONE, to=3.0):
        try:
            self.ser = serial.Serial(port=port, baudrate=b, parity=parity,
                            bytesize=size, stopbits=stops, timeout=to)
            self.open=True
        except:
            print("Error opening port")
            self.open = False

    def stresstest(self, n):
        ok_count = 0
        error_count = 0
        print("Sending %d 8192 byte blocks of random data from 0x00-0xFF at " % n)
        print("230400 baud, n, 8, 1")
        for i in range(n):
            print("Sending block#%d" % (i+1))
            outblock = random.randbytes(8192)
            print("\t", str(outblock[0:10])+"......"+str(outblock[-11:-1]))
            self.ser.write(outblock)
            time.sleep(10.0)
            inblock = self.ser.read(8192)
            # print(inblock)
            print("\t\tReceived: %d bytes" % len(inblock))
            if inblock == outblock:
                print("\t\tMatch: True")
                ok_count += 1
            else:
                print("\t\tMatch: False")
                error_count += 1
        print("\n%d attempts" % n)
        print("%d OK" % ok_count)
        print("%d FAILED" % error_count)
        return

if __name__ == "__main__":
    SERIAL_PORT = "COM17"
    toy = WDC_tester(SERIAL_PORT, 230400, serial.PARITY_NONE, serial.EIGHTBITS, serial.STOPBITS_ONE, 3.0)
    print(toy)
    toy.stresstest(10)
    #toytalk._send_command(b'\x03', 10)
    #toytalk._read()
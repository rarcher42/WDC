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
        start_time = time.time()
        for i in range(n):
            print("Sending block#%d - %d OK %d FAIL" % ((i+1), ok_count, error_count))
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
        elapsed = time.time() - start_time
        print("\n%d attempts" % n)
        print("%d OK" % ok_count)
        print("%d FAILED" % error_count)
        num = 8192 * n
        print("%d bytes in %f seconds" % (num, elapsed))
        print("Throughput = %.2f bytes/sec" % (float(num)/elapsed))

        return

if __name__ == "__main__":
    SERIAL_PORT = "COM17"
    toy = WDC_tester(SERIAL_PORT, 230400, serial.PARITY_NONE, serial.EIGHTBITS, serial.STOPBITS_ONE, 3.0)
    print(toy)
    toy.stresstest(100)

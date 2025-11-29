import random
import time
import sys
import serial
''' 
01 READ BYTES:  01 SAL SAH SAB BCL BCH NLO NHI     (read N+1 bytes 1-256)
02 WRITE BYTES  02 SAL SAH SAB B0 B1 B2..... BN  (use CMD_IX to find last byte to write)
03 JUMP TO ADDRESS  03 SAL SAH SAB  
'''
class Frame:
    ''' Encapsulate a frame '''
    def __init__(self):
        self.SOF = 0x02
        self.ESC = 0x10
        self.EOF = 0x03
        self.SIZE_CMD_BUF = 512
    ''' 
        Encapsulate the payload to exclude SOF & EOF with ESC encoding 
        A wire frame begins with SOF and ends with EOF for ease of decoding 
    '''
    def wire_encode(self, rawpay):
        outbytes = bytes()
        outbytes += self.SOF.to_bytes(1)  # Start the wire frame
        for b in rawpay:
            if b == self.SOF: 
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x11.to_bytes(1)
            elif b == self.ESC:
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x12.to_bytes(1)
            elif b == self.EOF:
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x13.to_bytes(1) 
            else:
                outbytes += b.to_bytes(1)
        outbytes += self.EOF.to_bytes(1)  # End the wire frame
        return outbytes  

    ''' 
        Reverse payload encapsulation to yield original payload.  This
        involves discarding the intial SOF and terminal EOF, and 
        reversing all escaped data inside the payload to restore their values.
    '''
    def wire_decode(self, wire):
        state = 0
        inp = 0
        cmd_ptr = 0

        while True:
            if (cmd_ptr >= self.SIZE_CMD_BUF):
                print("OVERFLOW!!!!!!!!!!!!!!!!!!!!")
                state = 0
                exit(-1)
                continue

            # print("State = ", state)
            # INIT state
            if state == 0:
                state = 1
                cmd_ptr = 0
                outbytes = bytes()
                inp = 0
                error = False
                continue

            # AWAIT state
            elif state == 1:
                b = wire[inp]
                inp += 1
                if b == self.SOF:
                    state = 2
                continue
                
            # COLLECT state 
            elif state == 2:
                b = wire[inp]
                inp += 1
                if b == self.SOF:
                    cmd_ptr = 0
                    continue
                elif b == self.EOF:
                    state = 4
                    continue
                elif b == self.ESC:
                    state = 3
                    continue
                else:
                    outbytes += b.to_bytes(1)
                    cmd_ptr += 1
                    continue    
    
            # TRANSLATE state
            elif state == 3:
                b = wire[inp]
                inp += 1
                if b == self.SOF:
                    cmd_ptr = 0
                    outbytes = bytes()
                    continue
                elif b == self.EOF:
                    state = 0
                    continue
                elif b == 0x11:
                    outbytes += self.SOF.to_bytes(1)
                    cmd_ptr += 1
                    state = 2 
                    continue
                elif b == 0x12:
                    outbytes += self.ESC.to_bytes(1)
                    cmd_ptr += 1
                    state = 2
                    continue
                elif b == 0x13:
                    outbytes += self.EOF.to_bytes(1)
                    cmd_ptr += 1
                    state = 2
                    continue
                continue

            # PROCESS state
            elif state == 4:
                state = 0
                return outbytes
            # INVALID state
            else:
                print("INVALID STATE")
                sys.exit(-2)
                state = 0
                continue
               

class FIFO:
    def __init__(self, port='COM17', b=1200, parity=serial.PARITY_NONE, size=serial.EIGHTBITS,
                 stops=serial.STOPBITS_ONE, to=3.0):
        try:
            self.ser = serial.Serial(port=port, baudrate=b, parity=parity,
                            bytesize=size, stopbits=stops, timeout=to)
            self.open=True
        except:
            print("Error opening port")
            self.open = False

    def write(self, s):
        self.ser.write(s)
        return
        
    def read(self):
        outb = b''
        outb = self.ser.read_until(b'\x03')
        return outb
        
    def close(self):
        self.ser.close()
        return

def dump_hex(sa_24, data):
    count = 0
    for b in data:
        if (count == 0):
            s = "\n%06X:" % sa_24
            print(s, end="")
        s = " %02X" % b
        print(s, end="")
        count += 1
        sa_24 += 1
        if count > 15:
            count = 0
    return

def read_mem_cmd(sa_24, nbytes):
    assert(nbytes < 257)
    sab = ((sa_24 >> 16) & 0xFF).to_bytes(1, 'little')
    sah = ((sa_24 >> 8) & 0xFF).to_bytes(1, 'little')
    sal = ((sa_24) & 0xFF).to_bytes(1, 'little')
    nbl = (nbytes & 0xFF).to_bytes(1, 'little')
    nbh = ((nbytes >> 8) & 0xFF).to_bytes(1, 'little')
    return  b'\x01'+sal+sah+sab+nbl+nbh
    
def write_mem_cmd(sa_24, data):
    assert(len(data) < 257)
    sab = ((sa_24 >> 16) & 0xFF).to_bytes(1, 'little')
    sah = ((sa_24 >> 8) & 0xFF).to_bytes(1, 'little')
    sal = ((sa_24) & 0xFF).to_bytes(1, 'little')
    ob = b'\x02' + sal + sah + sab 
    for b in data:
        ob += b.to_bytes(1, "little")
    print("ob=", ob)
    return ob
    
SERIAL_PORT = "COM4"  
if __name__ == "__main__":
    fifo = FIFO(SERIAL_PORT, 921600, serial.PARITY_NONE, serial.EIGHTBITS, serial.STOPBITS_ONE, 0.1)
    v = Frame()
    fifo.read()     # Ditch any power on messages or noise bursts
   
    '''
    # Test JML
    inf = b'\x03\00\xF8\00'
    outf = v.wire_encode(inf)
    # print("Writing ", outf)
    fifo.write(outf)
    time.sleep(0.1)
    reinf = fifo.read()
    print(reinf)
    time.sleep(5.0)
    reinfo = fifo.read()
    print(reinfo)
    
    exit(0)
    '''
    '''
    inf = write_mem_cmd(0x0200, b'0123456789ABCDEF!')
    outf = v.wire_encode(inf)
    fifo.write(outf)
    reinf = fifo.read()
    rereinf = v.wire_decode(reinf)
    print(rereinf)
   
    inf = read_mem_cmd(0x0200, 17)
    outf = v.wire_encode(inf)
    fifo.write(outf)
    reinf = fifo.read()
    rereinf = v.wire_decode(reinf)
    dump_hex(0x000200, rereinf)
    exit(0)

    '''

    while True:
        n = random.randrange(1, 256)
        inf = b'E'
        for i in range(n):
            inf += random.randrange(0, 255).to_bytes(1)
        outf = v.wire_encode(inf)
        # print("Writing ", outf)
        fifo.write(outf)
        #time.sleep(0.1)
        reinf = fifo.read()
        #print("Reading ", reinf)
        rereinf = v.wire_decode(reinf)
        print(len(rereinf), "\t", rereinf == inf)
        if rereinf != inf:
            break
    
    '''
    start_t = time.time()
    for sa in range(0, 0x010000, 256):
        inf = read_mem_cmd(sa, 256)
        outf = v.wire_encode(inf)
        meow = v.wire_decode(outf)
        if meow != inf:
            print("ERROR in encode/decode on Python side!")
        #print("Writing ", outf)
        fifo.write(outf)
        reinf = fifo.read()
        #print("Reading ", reinf)
        rereinf = v.wire_decode(reinf)
        #print(len(rereinf), rereinf)
        dump_hex(sa, rereinf)
    end_t = time.time()
    print("\n\nDumped 64K byte in %10.1f seconds" % (end_t - start_t))
    print("Rate = %10.1f bytes/second: " % (65536.0 / (end_t - start_t)))
    '''
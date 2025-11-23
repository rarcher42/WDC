import random
import time
import sys



''' 
01 READ BYTES:  01 SAL SAH SAB BCL BCH
02 WRITE BYTES  02 SAL SAH SAB B0 B1 B2..... BN
03 JUMP TO ADDRESS  03 SAL SAH SAB  
04 CALL TO ADDRESS  04 SAL SAH SAB

'''
class Frame:
    ''' Encapsulate a frame '''
    def __init__(self):
        self.SOF = 0x42
        self.ESC = 0x55
        self.EOF = 0x00
        self.SIZE_CMD_BUF = 1024
    ''' 
        Encapsulate the payload to exclude SOF & EOF with ESC encoding 
        A wire frame begins with SOF and ends with EOF for ease of decoding 
    '''
    def wire_encode(self, rawpay):
        # print("rawpay= ", rawpay)
        outbytes = bytes()
        outbytes += self.SOF.to_bytes(1)  # Start the wire frame
        for b in rawpay:
            if b == self.SOF: 
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x01.to_bytes(1)
            elif b == self.ESC:
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x02.to_bytes(1)
            elif b == self.EOF:
                outbytes += self.ESC.to_bytes(1)
                outbytes += 0x03.to_bytes(1) 
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
                elif b == 0x01:
                    outbytes += self.SOF.to_bytes(1)
                    cmd_ptr += 1
                    state = 2 
                    continue
                elif b == 0x02:
                    outbytes += self.ESC.to_bytes(1)
                    cmd_ptr += 1
                    state = 2
                    continue
                elif b == 0x03:
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
        # end
        
if __name__ == "__main__":
    v = Frame()
   
    for i in range(10000):
        n = random.randrange(1, 1024)
        inf = random.randbytes(n)
        outf = v.wire_encode(inf)
        reinf = v.wire_decode(outf)
        print(inf == reinf, "\t", len(outf))
        if inf != reinf:
            print("ERROR")
            sys.exit(-1)

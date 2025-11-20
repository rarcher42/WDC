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
        self.SOF = 0xAA
        self.ESC = 0x55
        self.EOF = 0x00 

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
    def wire_decode(self, payload):
        outbytes = bytes()
        state = 0
        error = False
        
        for b in payload:
            if state == 0: 
                if b == self.SOF or b == self.EOF:
                    continue # discard SOF EOF (discard OOB frame markers)
                if b == self.ESC:
                    state = 1
                else:
                    outbytes += b.to_bytes(1)
            else:
                if b == 0x01:
                    outbytes += self.SOF.to_bytes(1)
                    state = 0
                elif b == 0x02:
                    outbytes += self.ESC.to_bytes(1)
                    state = 0
                elif b == 0x03:
                     outbytes += self.EOF.to_bytes(1)
                     state = 0
                else:
                    error = True

        if error == True:
            return None
        else: 
            return outbytes 


if __name__ == "__main__":
    v = Frame()
   
    for i in range(100000):
        n = random.randrange(1,32768)
        inf = random.randbytes(n)
        outf = v.wire_encode(inf)
        reinf = v.wire_decode(outf)
        print(len(outf), inf == reinf)
        # print(outf)
        if inf != reinf:
            print("ERROR")
            sys.exit(-1)


def calc_checksum(line):
    print("calc_checksum({:s})".format(line))
    sum = 0
    assert line[0] == 'S'
    rectype = int(line[1])
    print("rectype=", rectype)
    assert rectype in [0,1,2,5,6,8,9]
    byte_count = int(line[2:4], 16)

    for i in range(byte_count):
        newbyte = int(line[2*i+2:2*i+4], 16)
        sum += newbyte
    checksum = (~sum & 0xFF)
    return checksum

def conv_s1_to_s2(s1_line):
    print("\n\n\n\n in=", s1_line)
    rectype = int(s1_line[1])
    assert rectype in [0, 1, 5, 9]
    if rectype == 0:
        return s1_line
    elif rectype == 1:
        byte_count = int(s1_line[2:4], 16) + 1
        rt = "S2%02X" % byte_count
        rt += "00"  # Leading zero for address
        rt += s1_line[4:-1]
        chksum = calc_checksum(rt)
        cstr = "%02X" % chksum
        rt = rt[0:-2] + cstr
        print("out=", rt)
        return rt
    elif rectype == 2:
        return s1_line
    elif rectype == 5:
        byte_count = int(s1_line[2:4], 16) + 1
        rt = "S6%02X" % byte_count
        rt += "00"  # Leading zero for address
        rt += s1_line[4:-1]
        chksum = calc_checksum(rt)
        cstr = "%02X" % chksum
        rt = rt[0:-2] + cstr
        print("out=", rt)
        return rt
    elif rectype == 9:
        byte_count = int(s1_line[2:4], 16) + 1
        rt = "S8%02X" % byte_count
        rt += "00"  # Leading zero for address
        rt += s1_line[4:-1]
        chksum = calc_checksum(rt)
        cstr = "%02X" % chksum
        rt = rt[0:-2] + cstr
        print("out=", rt)
        return rt
        byte_count = int(s1_line[2:4], 16) + 1
        rt = "S2%02X" % byte_count
        rt += "00"  # Leading zero for address
        rt += s1_line[4:-1]
        chksum = calc_checksum(rt)
        cstr = "%02X" % chksum
        rt = rt[0:-2] + cstr
        print("out=", rt)
        return rt

if __name__ == '__main__':
    FILENAME = input("Filename?:")
    print("Converting %s --> %s" % (FILENAME+".hex", FILENAME+".s28"))
    fh = open(FILENAME+".hex", 'r')
    srec_list = fh.readlines()
    fw = open(FILENAME+".s28", "w")
    outs = ""
    for srl in srec_list:
        outs += conv_s1_to_s2(srl) + "\r\n"
    fw.write(outs)
    fh.close()
    fw.close()
    
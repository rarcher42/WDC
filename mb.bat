ca65 -g -l min_mon.lst --feature labels_without_colons  min_mon.asm
ld65 -C /usr/local/share/cc65/cfg/wdc.cfg -vm -m basic.map -o basic.bin min_mon.o

import serial
import time
import random

print("Opening COM...")

ser = serial.Serial("COM5", 9600, timeout=1)

print("COM openned...")

try:
    while True:
        print("---Loop running---")
        bpm = random.randint(60, 120)
        message = f"BPM:{bpm}\n"
        #ser.write(b"Hello Phone\n")
        ser.write(message.encode())
        print("Sent:", message.strip())
        time.sleep(2)

except KeyboardInterrupt:
    print("\nStopped")
    ser.close()
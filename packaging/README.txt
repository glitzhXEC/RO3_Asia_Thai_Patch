RO3 Asia แพตช์ภาษาไทย
====================

แพตช์นี้แปลรายละเอียดสกิล เควส และไอเทมเป็นภาษาไทย เมนูและชื่อเฉพาะในเกมยังเป็นภาษาอังกฤษ

ติดตั้งแบบง่าย
1. ปิดเกม RO3 และ RO3AsiaLauncher
2. เปิด Install-Thai.bat
3. เลือกโฟลเดอร์ Client ที่มีไฟล์ ro3.exe
4. รอข้อความ [OK] Thai patch installed แล้วเปิดเกมผ่าน RO3AsiaLauncher

หรือจะลากไฟล์ ro3.exe หรือโฟลเดอร์ Client ไปวางบน Install-Thai.bat ก็ได้

ติดตั้งผ่าน CMD
เปิด CMD แล้วใช้คำสั่งต่อไปนี้ โดยเปลี่ยนตำแหน่งโฟลเดอร์แพตช์และเกมให้ตรงกับเครื่อง:

  cd /d "C:\Path\To\ExtractedPatch"
  Install-Thai.bat "C:\Games\RO3\Client"

ติดตั้งผ่าน PowerShell
เปิด PowerShell แล้วใช้คำสั่งต่อไปนี้ โดยเปลี่ยนตำแหน่งโฟลเดอร์แพตช์และเกมให้ตรงกับเครื่อง:

  Set-Location "C:\Path\To\ExtractedPatch"
  .\Install-Thai.bat "C:\Games\RO3\Client"

โฟลเดอร์ Client ที่ระบุต้องมีไฟล์ ro3.exe อยู่ข้างใน

อัปเดต
- ปิดเกมและ Launcher แล้วเปิด Update-Thai.bat เพื่อดาวน์โหลดรุ่นล่าสุด
- ระบุโฟลเดอร์เกมได้ เช่น Update-Thai.bat "C:\Games\RO3\Client"
- ติดตั้งจากไฟล์ในโฟลเดอร์นี้โดยไม่ดาวน์โหลด ใช้ Update-Thai.bat --local "C:\Games\RO3\Client"

ถ้าคำแปลไม่ขึ้น
ปิดเกมและ Launcher แล้วเปิด Install-Thai.bat อีกครั้ง จากนั้นตรวจว่าเลือกโฟลเดอร์ที่มี ro3.exe และเปิดเกมผ่าน RO3AsiaLauncher

กู้คืนหลังเกมซ่อมไฟล์
- ปิดเกมและ Launcher แล้วเปิด Recover-Thai.bat
- ถ้าเพิ่งใช้คำสั่ง Repair ของเกม ให้ใช้ Recover-After-Official-Repair.bat หลัง Repair เสร็จและเปิดเกมได้แล้ว โปรแกรมจะขอให้พิมพ์ REPAIRED เพื่อยืนยัน

ถอนการติดตั้ง
- ปิดเกมและ Launcher แล้วเปิด Uninstall-Thai.bat
- หาก BepInEx มีอยู่ก่อนติดตั้งแพตช์ ตัวถอนติดตั้งจะไม่ลบให้อัตโนมัติ เพื่อป้องกันการกระทบโปรแกรมหรือม็อดอื่น

แพตช์นี้เป็นผลงานชุมชน ไม่ใช่แพตช์ทางการของเกม ชื่อเฉพาะและค่าสถานะบางคำตั้งใจคงเป็นภาษาอังกฤษ

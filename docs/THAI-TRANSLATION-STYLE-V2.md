# คู่มือสำนวนคำแปลไทย V2

เอกสารนี้เป็นมาตรฐานสำหรับการแปลรายละเอียดสกิล ไอเทม และเควสใหม่ทั้งชุด
เป้าหมายคือให้ข้อความอ่านเป็นภาษาไทยธรรมชาติ กระชับ และใช้คำเดียวกันตลอดเกม
โดยไม่ทำลายตัวแปรหรือรูปแบบที่เกมใช้

## 1. ขอบเขต

แปลเฉพาะรายละเอียดใน namespace ที่อนุญาต:

- `101103`, `102203`, `108001` — รายละเอียดสกิลและเอฟเฟกต์
- `123901`, `100501` — รายละเอียดไอเทม อาหาร และยา
- `131500`, `131502`, `131506` — รายละเอียดและวัตถุประสงค์เควส

คงข้อความต่อไปนี้เป็นภาษาอังกฤษ:

- ชื่อสกิล แผนที่ มอนสเตอร์ NPC สัตว์เลี้ยง และไอเทม
- ชื่อสถานะหรือกลไกที่เกมแสดงเป็นชื่อเฉพาะ เช่น `Endure`, `Control Immunity`
- ชื่ออาวุธและคลาส เช่น `Dagger`
- ค่าสถานะและตัวย่อ เช่น `STR`, `AGI`, `VIT`, `INT`, `DEX`, `LUK`,
  `P.ATK`, `M.ATK`, `P.DEF`, `M.DEF`, `ASPD`, `MSPD`, `HIT`, `Flee`, `CRIT`
- สูตรคำนวณและข้อความภายในวงเล็บชื่อเฉพาะ เช่น `[ Hammer Fall ]`

ห้ามเติมคำแปลไทยในวงเล็บต่อท้ายชื่ออังกฤษ เช่น `Dagger (มีด)`

## 2. คำศัพท์หลัก

| English | ใช้คำว่า |
| --- | --- |
| Neutral | `Neutral` |
| Fire / Water / Wind / Earth / Holy / Shadow / Ghost | คงชื่อธาตุภาษาอังกฤษ |
| Physical Attack / PATK / P.ATK | `P.ATK` |
| Magic Attack / MATK / M.ATK | `M.ATK` |
| Physical Damage / P.DMG | `P.DMG` |
| Magic Damage / M.DMG | `M.DMG` |
| Physical Defense / PDEF / P.DEF | `P.DEF` |
| Magic Defense / MDEF / M.DEF | `M.DEF` |
| Physical Penetration / P.PEN | `P.PEN` |
| Magic Penetration / M.PEN | `M.PEN` |
| Physical Damage Reduction | `P.DMG Reduction` หรือ `P.DMG Reduc.` ตามพื้นที่ UI |
| Magic Damage Reduction | `M.DMG Reduction` หรือ `M.DMG Reduc.` ตามพื้นที่ UI |
| Physical Damage Increase | `P.DMG Increase` |
| Magic Damage Increase | `M.DMG Increase` |
| Physical Damage Bonus | `P.DMG Bonus` |
| Magic Damage Bonus | `M.DMG Bonus` |
| True Damage / Fixed Damage | `True Damage` |
| Critical Damage | `CRIT DMG` |
| Critical Resistance | `CRIT RES` |
| Attack Speed | `ASPD` |
| Movement Speed | `MSPD` |
| Variable Cast Time / Cast Time | `VCT` |
| Fixed Cast Time | `FCT` |
| Cast Delay / Global Delay | `Cast Delay` |
| Cooldown | `CD` |
| Hit | `HIT` |
| Flee / Dodge | `Flee` |
| ST | `Single Target` |
| melee | ระยะประชิด |
| ranged | ระยะไกล |
| Adaptive Damage | `Adaptive Damage` |
| Adaptive ATK | `Adaptive ATK` |
| deal damage | สร้าง… `P.DMG` / `M.DMG` …แก่… |
| total damage | `P.DMG` / `M.DMG` รวม |
| up to N enemies | ศัตรูสูงสุด N ตัว |
| within N meters | ภายในระยะ N เมตร |
| within an N-meter radius | ภายในรัศมี N เมตร |
| gain | ได้รับ |
| grant | มอบ…ให้… |
| inflict | ทำให้ติดสถานะ… |
| increase damage dealt | เพิ่มความเสียหายที่สร้าง |
| Internal Cooldown | เอฟเฟกต์นี้มี `CD`… |
| master (pet context) | เจ้าของ |
| self / caster | ตนเอง / ผู้ใช้ ตามบริบท |
| ally | พันธมิตร |
| target | เป้าหมาย |
| sec / seconds | วินาที |

ใช้ `สกิล` เป็นคำหลัก ไม่สลับกับ `ทักษะ` ภายในคำอธิบายชุดเดียวกัน

## 3. รูปประโยค

เรียงข้อมูลตามลำดับนี้เมื่อทำได้:

1. การกระทำของสกิล
2. ชนิดและสูตรความเสียหาย
3. จำนวนและขอบเขตเป้าหมาย
4. สถานะหรือเอฟเฟกต์เพิ่มเติม
5. ระยะเวลาและคูลดาวน์

ตัวอย่าง:

> เรียกเงาจำนวนมากออกมาโจมตีศัตรู สร้าง `Neutral P.DMG` ระยะประชิดรวมเท่ากับ
> `P.ATK*...` แก่ศัตรูสูงสุด `${2}` ตัวภายในรัศมี `${1}` เมตร และได้รับ
> `[ Endure ]` ขณะร่ายสกิลนี้

หลีกเลี่ยงสำนวนแปลตรงตัวที่ไม่เป็นธรรมชาติ เช่น:

- `Neutral Physical Damage` → ~~ความเสียหายกายภาพไร้ธาตุ~~
- `Physical Attack` → ~~พลังโจมตีกายภาพ~~ หรือ ~~PATK~~
- `master` → ~~ปรมาจารย์~~ หรือ ~~ต้นแบบ~~
- `up to` → ~~ไปจนถึง~~
- `dealing` → ~~จัดการกับ~~
- `for ${1} seconds` → ~~สำหรับ `${1}` วินาที~~

## 4. การเว้นวรรค

- เว้นวรรคระหว่างตัวแปรกับหน่วย: `${1} เมตร`, `${2} วินาที`, `${3} ตัว`
- ไม่เว้นวรรคก่อน `%`: `${4}%`
- สูตรคำนวณไม่เติมช่องว่างใหม่โดยไม่จำเป็น:
  `P.ATK*^{1}${3}%*(${4}+ASPD*${5}%)^{2}`
- แท็กสีต้องชิดกับข้อความที่ครอบ:
  `^{1}${3}%^{2}`, `^{3}^{4}[ Endure ]^{5}^{6}`
- ชื่อหรือสถานะที่ต้นฉบับครอบด้วย `【…】` หรือ `[…]` ให้ใช้รูปแบบ
  `[ Name ]` เสมอ เช่น `[ Endure ]`, `[ Stun ]`, `[ Falcon Assault ]`
- เว้นวรรคก่อนและหลังสูตรเมื่อสูตรทำหน้าที่เป็นส่วนหนึ่งของประโยค
- หลัง `\n` ไม่เติมช่องว่างนำหน้าบรรทัดโดยไม่มีเหตุผล
- ใช้เครื่องหมายวรรคตอนแบบเดียวกันตลอดข้อความ และไม่ทิ้งจุดภาษาอังกฤษ
  ต่อท้ายประโยคไทยโดยไม่จำเป็น

## 5. ตัวแปรและแท็กที่ห้ามแก้

ต้องคงจำนวนและลำดับของรายการต่อไปนี้ให้ตรงกับต้นฉบับ:

- `${1}`, `@{1}`, `{1}` และตัวเลขลำดับอื่น
- `^{1}`, `^{2}` และ style marker ทุกตัว
- `<color>`, `<link>` และแท็ก HTML-like
- `\n`, `\t` และ escape อื่น
- ข้อความภายใน `[]` และ `【】` ห้ามแปลหรือเปลี่ยนชื่อ แต่รูปแบบปลายทางใช้
  `[ Name ]`

ห้ามย้าย style marker ไปครอบข้อความคนละส่วนเพียงเพื่อให้ประโยคอ่านง่ายขึ้น

## 6. ขั้นตอนตรวจทุกข้อความ

1. อ่านต้นฉบับให้ครบก่อนแปล ไม่แทนคำทีละคำ
2. ระบุชื่อเฉพาะ สูตร ตัวแปร และ style marker
3. เขียนประโยคไทยใหม่ตามความหมาย
4. ตรวจคำศัพท์กับตารางในเอกสารนี้
5. ตรวจช่องว่างรอบตัวแปร หน่วย และแท็ก
6. ตรวจ Game Preview ใน RO3 Translation Editor
7. รัน `python scripts/validate-thai-payload.py` ก่อน commit

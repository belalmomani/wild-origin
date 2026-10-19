# البطل
`hero.glb` مجسم رجل بالغ بهيكل عظمي من 16 عظمة (أسماؤها هي أسماء مفاصل `scripts/character.gd`: hips, spine, chest, head, shL/elL/handL, shR/elR/handR, hipL/knL/anL, hipR/knR/anR) ووزن جلد سلس، وخامات PBR مضمّنة.
- يُعاد توليده بـ `python3 tools/hero_export.py` (يحتاج numpy وPillow).
- الحركات إجرائية بالكود (لا مقاطع أنيميشن داخل الملف). نقطتا تثبيت الأدوات: `ToolSocket_R` و`ToolSocket_L`.
- يمكنك استبداله بنموذج آخر بنفس أسماء العظام، أو بنموذج به `AnimationPlayer` (idle/walk/run) فيُستخدم عندها مسار الأنيميشن الجاهز.

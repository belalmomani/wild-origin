الأصول البصرية الأصلية المستخرجة من Hunting Clash v5.43.2 (بدون أي كود)

الملفات
- wolf_LOD0.glb / wolf_LOD1.glb : الذئب الشمالي الغربي (NORTHWESTER_WOLF) — 1746 رأسًا / 1125، 53 عظمة
- bear_LOD0.glb / bear_LOD1.glb : الدب الأسود (Black_bear) — 2737 رأسًا / 1581، 37 عظمة
- LOD0 يحتوي على Mesh + Skin + الخامة + كل التحريكات الأصلية (wolf 25 تحريكًا، bear 22). LOD1 بدون تحريكات (نفس الهيكل).
- wolf_Northwestern_Wolf_Diffuse.png / bear_texture_1k.png : خامة اللون 1024x1024 (ETC2 الأصلية مفكوكة، بدون أي تعديل في الألوان)
- wolf_FlowMap.png / bear_blackBear_FlowMap.png : خريطة اتجاه الفرو 256x256 (للمادة Fur فقط، ليست خامة لون)
- preview_check.png : فحص تشغيل التحريكات على النماذج المصدّرة

التحويلات
- محور X معكوس (يونيتي → glTF يمينية اليد) مع قلب ترتيب المثلثات؛ UV: v = 1 - v.
- التحريكات مأخوذة من Streamed/Constant clips وحُوّلت إلى عينات 30 إطارًا/ث (LINEAR)، المسارات مطابقة لأسماء العظام عبر CRC32 (تطابق 58/58 للذئب و55/55 للدب).
- الهيكل = شجرة Transform الأصلية؛ inverseBindMatrices = bindposes الأصلية.

سلسلة الاعتماديات (كلها موجودة في الأرشيف المرسل)
الذئب:
  animals/montana/canis_lupus_occidentalis/prefab  (CAB-c0f5876e6d9ea4037bfd0175cc180655)  -> الخامة Northwestern_Wolf_Diffuse + مواد canis_lupus_occidentalis
  animals/montana/wolf_common                      (CAB-8461efe426eb41b99cb237b096f802c6)  -> Mesh LOD0/LOD1 + الهيكل + التحريكات + FlowMap.Wolf
الدب:
  animals/montana/ursus_americanus_americanus/prefab     (CAB-35027cf8c93de2069c39d293b6e528c8)
  animals/montana/ursus_americanus_americanus/resources  (CAB-8cfaa971598f86be99266b1a17266091)  -> Mesh LOD0/LOD1 + الهيكل + التحريكات + الخامة "texture 1k" + blackBear_FlowMap + المواد blackBearFur/NoFur
ملف animals/common (CAB-028698d2295f2d728b3019c188762631) ليس مطلوبًا لهذه النماذج.

ملاحظات
- لا توجد ملفات ناقصة للمجسمين والخامات والتحريكات.
- مواد الفرو (Fur shader وخامات _FurTex/_FurDirTex) تعتمد على شيدر اللعبة، وإن لم تُعثر خامات الفرو الإضافية داخل الحزم المرسلة؛ المصدَّر مادة PBR بسيطة بخامة اللون الأصلية.
- لم يُنتج FBX (لا توجد أداة FBX في البيئة)؛ GLB يُفتح في Unity عبر glTFast أو في Blender.

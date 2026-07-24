# تصميم قاعدة البيانات (Database Design)
## المخرج 9 من 20 — ELH-PRIMARY1 (الترم الأول)

**مبني على:** SRS (المخرج 1، خصوصًا NFR-9 حماية بيانات الطفل)، Story World Design (المخرج 8، المحطات الست)، البنية المعلوماتية (المخرج 3).
**تنبيه:** هذه من أخطر مراحل المشروع فعلاً — أي خطأ في تصميم صلاحيات الجداول هنا قد يعرّض بيانات أطفال حقيقية. لذلك كل جدول أدناه مصحوب بملاحظة صلاحيات صريحة.
**التقنية المقترحة:** Supabase (PostgreSQL + Row Level Security)، اتساقًا مع NFR-17 في SRS.

---

## 1. مبدأ التصميم الأمني العام

- **Row Level Security (RLS) مفعّل إجباريًا على كل جدول بدون استثناء.**
- لا جدول واحد يُقرأ مباشرة من طرف الطالب إلا بيانات نفسه فقط.
- **لا يوجد أي حساب دخول لولي الأمر في قاعدة البيانات** — تطبيقًا للقرار المعتمد (لا Parent Dashboard). بيانات ولي الأمر تُخزَّن فقط كمعلومات تواصل (بريد إلكتروني) مرتبطة بسجل الطالب، وليست حسابًا له صلاحيات دخول.
- كل معرّف طالب (Student ID) هو UUID عشوائي — لا تُستخدم أرقام تسلسلية يمكن تخمينها.
- أي بيانات صوتية (تسجيلات Phonics) تُخزَّن في Storage منفصل بصلاحيات صارمة، وتُربط بمعرّف مشفّر وليس مباشرة برابط عام.

---

## 2. الجداول الأساسية

### 2.1 `students` — الطلاب
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | معرّف عشوائي |
| display_name | text | اسم الطالب الظاهر (اسم أول فقط، لا بيانات كاملة حساسة) |
| avatar_config | jsonb | تخصيصات أفاتار Adam إن وُجدت لاحقًا |
| current_unit_id | FK → units | آخر محطة وصلها في عالم إل |
| placement_result | jsonb | نتيجة اختبار تحديد المستوى (داخلي فقط، لا يُعرض للطالب كدرجة) |
| created_at | timestamp | |
| status | enum (active/paused/archived) | يديره المدير فقط |

**صلاحيات RLS:** الطالب يقرأ/يعدّل صف نفسه فقط (عبر session خاص به). المدير له صلاحية كاملة على كل الصفوف.

### 2.2 `guardians` — بيانات تواصل ولي الأمر (ليست حسابات دخول)
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| contact_email | text (مشفّر عند التخزين) | للاستخدام في إرسال التقارير فقط (FR-6.3) |
| contact_name | text | اختياري |

**صلاحيات RLS:** المدير فقط له صلاحية قراءة/كتابة. لا يوجد أي مستخدم من نوع "guardian" في نظام المصادقة (Auth) إطلاقًا — يحقق القرار المعتمد بعدم وجود لوحة تحكم لولي الأمر.

### 2.3 `admins` — حسابات المدير
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | مرتبط بجدول Auth |
| email | text | |
| role | enum | (قابلة للتوسعة لاحقًا لأدوار إدارية متعددة إن احتاج المشروع) |

### 2.4 `units` — المحطات الست (ثابتة، بيانات مرجعية)
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| order_index | int (1-6) | ترتيب المحطة بعالم إل |
| location_name | text | مثال: "بوابة إل" |
| learning_outcome_codes | text[] | مثال: [LO-U1-01, LO-U1-02, ...] — **بدون أي إشارة لمصدر المنهج** |
| phonics_letters | text[] | مثال: [Tt, Ii] |

**ملاحظة امتثال:** هذا الجدول **لا يحتوي إطلاقًا** على أي حقل باسم "curriculum_source" أو "ministry" أو ما شابه — الربط بالمنهج المصري موجود فقط في مستند Deliverable 2 الداخلي، وليس في قاعدة البيانات التشغيلية.

### 2.5 `unit_progress` — تقدّم كل طالب بكل مرحلة
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| unit_id | FK → units | |
| stage | enum | (Learning Goal, Story, Adventure, Game, Practice, Song, Phonics, Challenge, Assessment) |
| status | enum (locked/in_progress/completed) | يفرض عدم تخطي المراحل (FR-2.3) |
| completed_at | timestamp | |
| score_internal | jsonb | بيانات تقييم داخلية، لا تُعرض كـ"درجة" للطالب مطلقًا |

**صلاحيات RLS:** الطالب يقرأ صفوفه فقط (لعرض التقدم بواجهته)، لا يعدّل `score_internal` مباشرة أبدًا (تُحدَّث فقط عبر منطق خادم/Server-side).

### 2.6 `phonics_attempts` — محاولات النطق
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| unit_id | FK → units | |
| letter | text | |
| audio_storage_path | text | مسار في Storage منفصل، وليس رابطًا عامًا مباشرًا |
| accuracy_score | numeric | داخلي، يُستخدم لتحليلات Joe فقط |
| attempt_number | int | لا حد أقصى (FR-3.6) |
| created_at | timestamp | |

**حساسية خاصة:** التسجيلات الصوتية بيانات طفل حساسة جدًا (NFR-9) — تُحذف تلقائيًا بعد مدة محددة (تُحسم بالضبط في System Architecture) إلا إذا احتاجها تحليل نشِط، ولا تُستخدم خارج نطاق تحسين تجربة هذا الطالب نفسه.

### 2.7 `rewards` — نظام التحفيز
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| type | enum (star/coin/badge/medal/treasure) | |
| reference_unit_id | FK → units (nullable) | |
| awarded_at | timestamp | |

### 2.8 `ai_analytics` — تحليلات Joe (يخدم FR-8.x)
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| metric_type | enum (pronunciation, vocabulary, reading, listening, consistency, pace) | |
| value | numeric/jsonb | |
| period | daterange | لدعم التقارير الأسبوعية/الشهرية |
| generated_recommendation | text | ما يظهر لـ Joe كتوصية شخصية |

**صلاحيات RLS:** المدير يقرأ الكل. الطالب لا يصل لهذا الجدول مباشرة إطلاقًا — فقط عبر واجهة Joe المبسّطة (Personal Recommendation).

### 2.9 `reports` — تقارير أولياء الأمور
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| student_id | FK → students | |
| period_type | enum (weekly/monthly) | |
| pdf_storage_path | text | |
| generated_at | timestamp | |
| sent_status | enum (draft/sent/not_sent) | القرار بيد المدير فقط (FR-6.2/FR-7.8) |
| sent_at | timestamp (nullable) | |
| sent_to_guardian_id | FK → guardians (nullable) | |

**صلاحيات RLS:** المدير فقط — قراءة وكتابة كاملة. لا صلاحية لأي طرف آخر.

### 2.10 `video_library` — مكتبة الفيديو
| الحقل | النوع | ملاحظات |
|---|---|---|
| id | UUID (PK) | |
| title | text | |
| topic_category | text | تصنيف حسب الموضوع، وليس الوحدة (FR-4.2) |
| video_storage_path / external_url | text | |

---

## 3. مخطط العلاقات المبسّط (Entity Relationships)

```
students ──1:N── unit_progress ──N:1── units
students ──1:N── phonics_attempts ──N:1── units
students ──1:N── rewards
students ──1:N── ai_analytics
students ──1:N── reports ──N:1── guardians
students ──1:1── guardians (بيانات تواصل فقط)
admins   ──(صلاحية كاملة على كل الجداول عدا Auth الخاص بالطلاب)
```

---

## 4. ملاحظات لـ System Architecture (المخرج 10)

- كل عمليات الكتابة الحساسة (تحديث `score_internal`، `ai_analytics`، `sent_status`) تمر عبر طبقة خادم (Server-side Functions/Edge Functions) — لا كتابة مباشرة من العميل (Client) حتى لو كانت الصلاحيات تسمح تقنيًا، لتقليل مساحة الهجوم.
- سياسة حذف/أرشفة بيانات الطالب عند مغادرته المنصة نهائيًا يجب حسمها صراحة (Data Retention Policy) — تُفصَّل في Security Design (المخرج 17).

---

## الخطوة التالية

**الخطوة 10 — System Architecture**: تصميم البنية التقنية الكاملة (الخدمات، طبقة API، التخزين، التكامل بين Frontend/Backend/AI)، مبنيًا مباشرة على هذا التصميم لقاعدة البيانات.

هذا المستند يحتاج مراجعتك واعتمادك قبل بدء الخطوة 10 — خصوصًا مراجعة سياسات الصلاحيات (RLS) لأنها الأساس الأمني لكل ما يُبنى فوقها.

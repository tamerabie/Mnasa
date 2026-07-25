-- ============================================================
-- ELH-PRIMARY1 — Phase 2: تعديل مؤقت لسياسات RLS للتجربة فقط
-- ============================================================
-- ⚠️ تنبيه هام جدًا:
-- السياسات دي مؤقتة عشان نقدر نجرب أول وحدة كاملة من غير ما
-- نكون بنينا نظام مصادقة الطالب الكامل (Edge Function + JWT) لسه.
-- ده جزء متعمّد من خطة العمل التكرارية (MVP أول، تقوية أمنية بعدين) —
-- هيتقفل تمامًا ويتستبدل بنظام آمن حقيقي في "المرحلة 6: التقوية الأمنية"
-- من Roadmap، قبل أي إطلاق فعلي للمنصة لأطفال حقيقيين.
--
-- يُنفَّذ في Supabase → SQL Editor → Run
-- ============================================================

-- السماح المؤقت بإنشاء وقراءة حساب طالب من أي زائر (بدل المدير فقط)
create policy "temp_students_anon_insert" on students for insert
  with check (true);
create policy "temp_students_anon_select" on students for select
  using (true);

-- السماح المؤقت بقراءة/كتابة تقدّم الوحدات بدون تحقق JWT
create policy "temp_progress_anon_all" on unit_progress for all
  using (true) with check (true);

-- السماح المؤقت بمحاولات النطق
create policy "temp_phonics_anon_all" on phonics_attempts for all
  using (true) with check (true);

-- السماح المؤقت بالمكافآت
create policy "temp_rewards_anon_all" on rewards for all
  using (true) with check (true);

-- ============================================================
-- نهاية السكريبت المؤقت
-- ============================================================

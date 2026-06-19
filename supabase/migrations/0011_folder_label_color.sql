-- Catch SNS — 0011 폴더 레이블(글자) 색
-- null이면 기본(어두운 색).
alter table public.folders add column if not exists label_color smallint;

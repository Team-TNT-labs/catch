-- Catch SNS — 0010 폴더 모양/색 커스터마이즈
-- null이면 클라이언트가 id 기반 기본 모양/라임색으로 폴백.
alter table public.folders add column if not exists shape smallint;
alter table public.folders add column if not exists color smallint;

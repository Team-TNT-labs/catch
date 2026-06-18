-- Catch SNS — 0009 catches 권한 보정
-- 증상: authenticated 역할에 catches INSERT 권한이 없어 스티커 서버 업로드(upsert)가
--       "permission denied for table catches"로 실패 → 서버에 catch 행이 없어
--       좋아요(FK 위반)·댓글(RLS 위반)이 모두 막힘.
-- RLS는 행 단위 게이트일 뿐 테이블 권한과 별개라, 권한을 명시적으로 부여한다.
-- (0003의 update 컬럼 화이트리스트는 유지 — 클라가 like_count 등 직접 수정 차단)

grant select, insert, delete on public.catches to authenticated;

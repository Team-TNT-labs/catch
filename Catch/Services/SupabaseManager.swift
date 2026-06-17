import Foundation
import Supabase

/// Supabase 클라이언트 싱글톤. URL/anon key는 클라이언트 공개 가능 값.
enum SupabaseConfig {
    static let url = URL(string: "https://zvelkutowmkptbjqpvyx.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp2ZWxrdXRvd21rcHRianFwdnl4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2NjMzODIsImV4cCI6MjA5NzIzOTM4Mn0.VBvwJbb320JyUnep-B-oEZnmCculW_BXEFAEB2pY9XI"
}

enum Supa {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey
    )
}

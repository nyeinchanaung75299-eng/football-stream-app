import java.lang.reflect.Method;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import javax.tools.ToolProvider;

// Java's source launcher compiles the actual Android state helper, requiring
// no Android SDK, Kotlin compiler, test dependency or duplicate implementation.
class TestNativeSourceSessions {
    static int checks;
    static void expect(boolean condition, String description) {
        if (!condition) throw new AssertionError(description);
        checks++;
    }

    public static void main(String[] args) throws Exception {
        Path output = Files.createTempDirectory("nca-source-sessions-");
        try {
            var compiler = ToolProvider.getSystemJavaCompiler();
            if (compiler == null) throw new IllegalStateException("A JDK is required");
            int status = compiler.run(null, null, null, "-d", output.toString(),
                "user_app/android_patch/PlaybackSourceSessions.java");
            expect(status == 0, "Actual Android session helper must compile");
            try (var loader = new URLClassLoader(new java.net.URL[]{output.toUri().toURL()})) {
                Class<?> type = loader.loadClass("com.example.football_viewer.PlaybackSourceSessions");
                Object sessions = type.getConstructor().newInstance();
                Method begin = type.getMethod("begin", String.class);
                Method current = type.getMethod("isCurrent", String.class);
                Method enqueue = type.getMethod("enqueueIfOpening", String.class, String.class);
                Method register = type.getMethod("register", String.class);
                Method close = type.getMethod("close", String.class);
                expect(!(boolean) enqueue.invoke(sessions, "unopened", "[first]"), "Unknown sessions cannot queue");
                begin.invoke(sessions, "slow-launch");
                expect((boolean) enqueue.invoke(sessions, "slow-launch", "[first,backup]"), "Backups must survive an unregistered Activity");
                expect((boolean) enqueue.invoke(sessions, "slow-launch", "[first,backup,late]"), "Latest full snapshot replaces the earlier pending snapshot");
                // Registration is intentionally separate from enqueue: delivery
                // must work regardless of whether launch took 300ms or seconds.
                expect("[first,backup,late]".equals(register.invoke(sessions, "slow-launch")), "Slow registration must consume all accumulated backups");
                expect(register.invoke(sessions, "slow-launch") == null, "Pending update is consumed once");
                expect(!(boolean) enqueue.invoke(sessions, "slow-launch", "[extra]"), "Registered activities receive updates directly, not through a second queue");
                begin.invoke(sessions, "old-launch");
                enqueue.invoke(sessions, "old-launch", "[old] ");
                begin.invoke(sessions, "new-launch");
                expect(!(boolean) current.invoke(sessions, "old-launch"), "Newest opening session supersedes the old session");
                expect(!(boolean) enqueue.invoke(sessions, "old-launch", "[stale]"), "Old anchor cannot enqueue into the new player");
                enqueue.invoke(sessions, "new-launch", "[new] ");
                close.invoke(sessions, "old-launch");
                expect("[new] ".equals(register.invoke(sessions, "new-launch")), "Old Activity destruction cannot clear the new pending update");
                begin.invoke(sessions, "closed-launch");
                enqueue.invoke(sessions, "closed-launch", "[closed] ");
                close.invoke(sessions, "closed-launch");
                expect(register.invoke(sessions, "closed-launch") == null, "Closed launch cannot revive its pending update");
                expect(!(boolean) enqueue.invoke(sessions, "closed-launch", "[late]"), "Late completion after close must be rejected");
                begin.invoke(sessions, "bounded");
                expect(!(boolean) enqueue.invoke(sessions, "bounded", "x".repeat(2 * 1024 * 1024 + 1)), "Pending snapshot memory must be bounded");
                begin.invoke(sessions, "");
                expect(!(boolean) enqueue.invoke(sessions, "", "[legacy]"), "Legacy players without a session cannot accept late updates");
            }
            System.out.println(checks + " native source session checks passed.");
        } finally {
            try (var paths = Files.walk(output)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(path);
            }
        }
    }
}

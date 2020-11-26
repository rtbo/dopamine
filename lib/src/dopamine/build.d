module dopamine.build;

enum BuildId {
    meson,
}

interface BuildSystem
{
    BuildId id();
    void configure(string builddir);
    void build();
}

class MesonBuildSystem : BuildSystem
{
    override BuildId id() { return BuildSystem.meson; }
    override void configure(string builddir) {}
    override void build() {}
}

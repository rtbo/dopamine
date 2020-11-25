module dopamine.generator;

enum Gen {
    meson,
}

interface Generator
{
    Gen gen();
    void configure(string builddir);
    void build();
}

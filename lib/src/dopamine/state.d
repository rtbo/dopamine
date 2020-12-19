/// This module implements a kind of Directed Acyclic Graph
/// that ensures that necessary state is reached for each of
/// the packaging steps.
module dopamine.state;

import dopamine.archive;
import dopamine.build;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.source;

import std.exception;
import std.file;
import std.typecons;

abstract class PackageState
{
    import std.algorithm : all;

    private PackageDir _packageDir;
    private const(Recipe) _recipe;
    private PackageState[] _prereq;

    this(PackageDir packageDir, const(Recipe) recipe, PackageState[] prerequisites = null)
    in(packageDir.hasDopamineFile())
    {
        _packageDir = packageDir;
        _recipe = recipe;
        _prereq = prerequisites;
    }

    final @property PackageDir packageDir() const
    {
        return _packageDir;
    }

    final @property const(Recipe) recipe() const
    {
        return _recipe;
    }

    final @property bool reached()
    {
        if (!prerequisites.all!(p => p.reached))
            return false;
        return checkReached();
    }

    final void reach()
    out(; prerequisites.all!(p => p.reached) && reached)
    {
        foreach (pr; prerequisites)
        {
            pr.reach();
        }
        if (!reached)
        {
            doReach();
        }
    }

    final @property PackageState[] prerequisites()
    {
        return _prereq;
    }

    protected abstract bool checkReached()
    in(prerequisites.all!(p => p.reached));

    protected abstract void doReach()
    in(!reached)
    out(; reached);
}

class StateNotReachedException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

mixin template EnforcedState(E = StateNotReachedException)
{
    private string _enforceMsg;

    @property string enforceMsg() const
    {
        return _enforceMsg;
    }

    protected override void doReach()
    {
        throw new E(_enforceMsg);
    }
}

abstract class ProfileState : PackageState
{
    private Profile _profile;

    this(PackageDir packageDir, const(Recipe) recipe)
    {
        super(packageDir, recipe);
    }

    @property const(Profile) profile()
    {
        return _profile;
    }

    protected override bool checkReached()
    {
        return _profile !is null;
    }
}

class UseProfileState : ProfileState
{
    this(PackageDir packageDir, const(Recipe) recipe, Profile profile)
    {
        super(packageDir, recipe);
        _profile = profile;
    }

    protected override void doReach()
    {
        assert(false);
    }
}

class UsePackageProfile : ProfileState
{
    this(PackageDir packageDir, const(Recipe) recipe)
    {
        super(packageDir, recipe);
    }

    protected override void doReach()
    {
        const path = packageDir.profileFile();
        enforce(exists(path), `Error: profile not set for "%s"`, packageDir.dir);
        _profile = Profile.loadFromFile(path);
    }
}

abstract class SourceState : PackageState
{
    string _sourceDir;

    this(PackageDir packageDir, const(Recipe) recipe)
    {
        super(packageDir, recipe);
    }

    @property string sourceDir()
    in(reached)
    {
        return _sourceDir;
    }

    protected override bool checkReached()
    {
        if (_sourceDir.length)
            return true;

        if (!recipe.outOfTree)
        {
            _sourceDir = packageDir.dir;
            return true;
        }

        auto flagFile = packageDir.sourceFlag();
        if (!flagFile.exists())
            return false;

        const sourceDir = flagFile.read();
        if (!exists(sourceDir) || !isDir(sourceDir))
            return false;

        if (timeLastModified(packageDir.dopamineFile()) >= flagFile.timeLastModified)
            return false;

        _sourceDir = sourceDir;
        return true;
    }
}

class EnforcedSourceState : SourceState
{
    mixin EnforcedState!();

    this(PackageDir packageDir, const(Recipe) recipe, string msg = "Error: Source is not ready!")
    {
        super(packageDir, recipe);
        _enforceMsg = msg;
    }
}

class FetchSourceState : SourceState
{
    this(PackageDir packageDir, const(Recipe) recipe)
    {
        super(packageDir, recipe);
    }

    override protected void doReach()
    in(recipe.outOfTree)
    {
        _sourceDir = recipe.source.fetch(packageDir);
    }
}

abstract class ConfigState : PackageState
{
    private ProfileState _profile;
    private SourceState _source;

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, SourceState source)
    {
        super(packageDir, recipe, [profile, source]);
        _profile = profile;
        _source = source;
    }

    @property const(Profile) profile()
    in(_profile.reached)
    {
        return _profile.profile;
    }

    @property string sourceDir()
    in(_source.reached)
    {
        return _source._sourceDir;
    }

    protected override bool checkReached()
    {
        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.configFlag();

        if (!flagFile.exists())
            return false;

        return flagFile.timeLastModified > packageDir.sourceFlag().timeLastModified
            && flagFile.timeLastModified > timeLastModified(packageDir.dopamineFile());
    }
}

class EnforcedConfigState : ConfigState
{
    mixin EnforcedState!();

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile,
            SourceState source, string msg = "Error: Build is not configured!")
    {
        super(packageDir, recipe, profile, source);
        _enforceMsg = msg;
    }
}

class DoConfigState : ConfigState
{
    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, SourceState source)
    {
        super(packageDir, recipe, profile, source);
    }

    protected override void doReach()
    {
        recipe.build.configure(sourceDir, packageDir.profileDirs(profile), profile);
    }
}

abstract class BuildState : PackageState
{
    private ProfileState _profile;

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, ConfigState config)
    {
        super(packageDir, recipe, [profile, config]);
        _profile = profile;
    }

    @property const(Profile) profile()
    in(_profile.reached)
    {
        return _profile.profile;
    }

    protected override bool checkReached()
    {
        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.buildFlag();

        if (!flagFile.exists())
            return false;

        return flagFile.timeLastModified > dirs.configFlag().timeLastModified
            && flagFile.timeLastModified > timeLastModified(packageDir.dopamineFile());
    }
}

class EnforcedBuildState : BuildState
{
    mixin EnforcedState!();

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile,
            ConfigState congig, string msg = "Error: Build is not ready!")
    {
        super(packageDir, recipe, profile, congig);
        _enforceMsg = msg;
    }
}

class DoBuildState : BuildState
{
    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, ConfigState config)
    {
        super(packageDir, recipe, profile, config);
    }

    protected override void doReach()
    {
        recipe.build.build(packageDir.profileDirs(profile));
    }
}

abstract class InstallState : PackageState
{
    private ProfileState _profile;

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, BuildState build)
    {
        super(packageDir, recipe, [profile, build]);
        _profile = profile;
    }

    @property const(Profile) profile()
    in(_profile.reached)
    {
        return _profile.profile;
    }

    protected override bool checkReached()
    {
        const dirs = packageDir.profileDirs(profile);
        auto flagFile = dirs.installFlag();

        if (!flagFile.exists())
            return false;

        return flagFile.timeLastModified > dirs.buildFlag().timeLastModified
            && flagFile.timeLastModified > timeLastModified(packageDir.dopamineFile());
    }
}

class EnforcedInstallState : InstallState
{
    mixin EnforcedState!();

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile,
            BuildState build, string msg = "Error: Build is not installed!")
    {
        super(packageDir, recipe, profile, build);
        _enforceMsg = msg;
    }
}

class DoInstallState : InstallState
{
    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, BuildState state)
    {
        super(packageDir, recipe, profile, state);
    }

    protected override void doReach()
    {
        recipe.build.install(packageDir.profileDirs(profile));
    }
}

abstract class ArchiveState : PackageState
{
    private ProfileState _profile;
    private string _file;

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, InstallState install)
    {
        super(packageDir, recipe, [profile, install]);
        _profile = profile;
    }

    @property const(Profile) profile()
    in(_profile.reached)
    {
        return _profile.profile;
    }

    @property string file()
    in(reached)
    {
        return _file;
    }

    protected override bool checkReached()
    {
        if (_file)
            return true;

        const file = packageDir.archiveFile(profile, recipe);
        if (!exists(file))
            return false;

        const dirs = packageDir.profileDirs(profile);

        const res = timeLastModified(file) > dirs.installFlag().timeLastModified
            && timeLastModified(file) > timeLastModified(packageDir.dopamineFile());

        if (res)
            _file = file;

        return res;
    }
}

class EnforcedArchiveState : ArchiveState
{
    mixin EnforcedState!();

    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile,
            InstallState install, string msg = "Error: Archive not created")
    {
        super(packageDir, recipe, profile, install);
        _enforceMsg = msg;
    }
}

class CreateArchiveState : ArchiveState
{
    this(PackageDir packageDir, const(Recipe) recipe, ProfileState profile, InstallState install)
    {
        super(packageDir, recipe, profile, install);
    }

    protected override void doReach()
    {
        const file = packageDir.archiveFile(profile, recipe);
        const dirs = packageDir.profileDirs(profile);

        ArchiveBackend.get.create(dirs.install, file);

        _file = file;
    }
}

module dopamine.lua;

import bindbc.lua;

void initLua() @system
{
    version (BindBC_Static)
    {
    }
    else
    {
        const ret = loadLua();
        if (ret != luaSupport)
        {
            if (ret == luaSupport.noLibrary)
            {
                throw new Exception("could not find lua library");
            }
            else if (luaSupport.badLibrary)
            {
                throw new Exception("could not find the right lua library");
            }
        }
    }
}

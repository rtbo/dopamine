#pragma once

#ifdef __cplusplus
extern "C"
{
#endif

#ifdef _WIN32
#   ifdef IS_DLL
#       ifdef PKGA_LIB
#           define API __declspec(dllexport)
#       else
#           define API __declspec(dllimport)
#       endif
#   else
#       define API
#   endif
#else
#   define API
#endif

API int func1(int x);

#ifdef __cplusplus
}
#endif

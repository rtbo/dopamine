function dependencies(profile)
    if profile.build_type == 'debug' then
        return {pkga = '>=1.0.0'}
    end
end

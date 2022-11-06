module options;

version(FeatureA)
{
    int featureA() {
        return 1;
    }
}

version(FeatureB)
{
    int featureB() {
        return 2;
    }
}

int totalFeatures()
{
    int result = 0;
    version(FeatureA)
        result += featureA();
    version(FeatureB)
        result += featureB();
    return result;
}

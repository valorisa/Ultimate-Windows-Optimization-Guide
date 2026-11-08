@{
    # WriteHost : scripts interactifs destines a la console, usage voulu.
    # PSReviewUnusedParameter : param de Show-Progress (ligne 13), repete dans les scripts (code amont).
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSReviewUnusedParameter'
    )
}

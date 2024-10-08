import Pkg

"""
The version of the `OMOPCommonDataModel.jl` Julia package.
"""
function version()::VersionNumber
    package_directory = dirname(dirname(@__FILE__))
    project_file = joinpath(package_directory, "Project.toml")
    version_string = Pkg.TOML.parsefile(project_file)["version"]
    version_number = VersionNumber(version_string)
    return version_number
end

"""
The version of the OMOP Common Data Model (CDM) being implemented.
"""
@inline function cdm_version()::VersionNumber
    return OMOP_CDM_VERSION
end

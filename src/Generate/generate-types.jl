const VERSION = "5.4"
const _default_input_file_name = join(["OMOPCDM_duckdb_", VERSION, "_ddl.sql"])
const _default_input_file_path = joinpath(dirname(dirname(dirname(@__FILE__))), "assets", _default_input_file_name)

"""
Generate the code for OMOPCommonDataModel from the DDL.
"""
@inline function generate(; input_file = _default_input_file_path,
                            output_file = join(["Outfiles/", VERSION, ".jl"]),
                            string_casing::F = pascalcase,
                            export_structs::Bool = true,
                            make_all_fields_optional::Bool = false,
                            struct_keyword = "struct") where F
    input_file_abspath = abspath(input_file)
    output_file_abspath = abspath(output_file)
    @info("Reading from input file \"$(input_file_abspath)\"")
    input_file_contents = read(input_file_abspath, String)
    mkpath(dirname(output_file_abspath))
    contents = _generate(input_file_contents;
                         export_structs = export_structs,
                         make_all_fields_optional = make_all_fields_optional,
                         string_casing = string_casing,
                         struct_keyword = struct_keyword)
    mkpath(dirname(output_file_abspath))
    rm(output_file_abspath; force = true, recursive = true)
    open(output_file_abspath, "w") do io
        println(io, contents)
    end
    @info("Wrote to output file \"$(output_file_abspath)\"")
    return output_file_abspath
end


@inline function _generate(input_file_contents::AbstractString;
                           string_casing::F,
                           export_structs::Bool,
                           make_all_fields_optional,
                           struct_keyword)::String where F
    pattern = r"CREATE TABLE @cdmDatabaseSchema.([\w_]*) \(([\s\S]*?)[\n\)];"
    all_match_positions = findall(pattern, input_file_contents)
    all_match_strings = String[input_file_contents[position] for position in all_match_positions]
    all_type_lines = String[
        _generate_single_type(pattern,
                              str;
                              export_structs = export_structs,
                              make_all_fields_optional = make_all_fields_optional,
                              string_casing = string_casing,
                              struct_keyword = struct_keyword) for str in all_match_strings
    ]
    num_generated_types = length(all_type_lines)
    output_lines = vcat(
        String["import Dates"],
        String["import DocStringExtensions"],
        all_type_lines,
    )
    output = join(output_lines, "\n\n\n")
    @info("Generated $(num_generated_types) types")
    return output
end

@inline function _generate_export_statement(structname::AbstractString,
                                            export_structs::Bool)::String
    if export_structs
        return "export $(structname)"
    else
        return ""
    end
end

@inline function _generate_single_type(pattern,
                                       str;
                                       string_casing::F,
                                       export_structs::Bool,
                                       make_all_fields_optional::Bool,
                                       struct_keyword)::String where F
    m = match(pattern, str)
    cdmname = m[1]
    _cdmname = strip(cdmname)
    _cdmname_lowercase = lowercase(_cdmname)
    _cdmname_uppercase = uppercase(_cdmname)
    @debug("Attempting to create a Julia type for the OMOP CDM table \"$(cdmname)\"")
    structname = string_casing(_cdmname)
    fields = String[]
    fieldcontentsraw = m[2]
    lines = strip.(split(strip(fieldcontentsraw), "\n"))
    for line in lines
        _line = strip(line)
        if length(_line) > 0
            field = _generate_single_field(_line;
                                           make_all_fields_optional = make_all_fields_optional)
            push!(fields, field)
        end
    end
    export_statement = _generate_export_statement(structname, export_structs)

    output_lines = vcat(
        String[export_statement],
        String[""],
        String["\"\"\""],
        String["CDM table name: $(_cdmname_uppercase)"],
        String[""],
        String["Julia struct name: $(structname)"],
        String[""],
        String["\$(DocStringExtensions.TYPEDEF)"],
        String["\$(DocStringExtensions.TYPEDFIELDS)"],
        String["\"\"\""],
        String["Base.@kwdef $(struct_keyword) $(structname) <: CDMType"],
        fields,
        String["end"],
    )
    output = join(output_lines, "\n")
    @debug("The OMOP CDM table \"$(cdmname)\" will become the Julia struct `$(structname)`")
    return output
end

@inline function _generate_single_field(line;
                                        make_all_fields_optional::Bool)::String
    _line = strip(line)
    pattern = r"^([\"\w]*)\s[\s]*([\w\d\(\)]*)\s[\s]*([\w ]*),?$"
    m = match(pattern, _line)
    field_name = m[1]
    _field_name = strip(strip(strip(field_name), Char['\"']))
    field_cdm_type = m[2]
    field_null_or_notnull = m[3]
    field_partialtype = _cdm_type_to_julia_partialtype(field_cdm_type)
    field_fulltype = _generate_full_fieldtype(field_partialtype,
                                              field_null_or_notnull;
                                              make_all_fields_optional = make_all_fields_optional)
    result = "    $(strip(_field_name))::$(strip(field_fulltype))"
    return result
end

@inline function _cdm_type_to_julia_partialtype(cdm_type)::String
    varchar_pattern = r"^varchar\([\d]*?\)$"i
    _cdm_type = lowercase(strip(cdm_type))
    if _cdm_type == "integer"
        return "Int"
    elseif _cdm_type == "date"
        return "Dates.DateTime"
    elseif _cdm_type == "timestamp"
        return "Dates.DateTime"
    elseif _cdm_type == "datetime2"
        return "Dates.DateTime"
    elseif _cdm_type == "numeric"
        return "Float64"
    elseif _cdm_type == "float"
        return "Float64"
    elseif _cdm_type == "text"
        return "String"
    elseif _cdm_type == "varchar(max)"
        return "String"
    elseif occursin(varchar_pattern, _cdm_type)
        return "String"
    end
    throw(ArgumentError("Invalid value for cdm_type: $(cdm_type)"))
end

@inline function _generate_full_fieldtype(partial_fieldtype,
                                          null_or_notnull;
                                          make_all_fields_optional::Bool)::String
    _null_or_notnull = strip(null_or_notnull)
    if _null_or_notnull == "NULL"
        return "Union{$(partial_fieldtype), Missing} = missing # optional"
    elseif _null_or_notnull == "NOT NULL"
        if make_all_fields_optional
            return "Union{$(partial_fieldtype), Missing} = missing # required"
        else
            return "$(partial_fieldtype) # required"
        end
    end
    throw(ArgumentError("Invalid value for `null_or_notnull`: $(null_or_notnull)"))
end

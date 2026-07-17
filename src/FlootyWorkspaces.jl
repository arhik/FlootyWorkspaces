module FlootyWorkspaces

using FlootyAbstract
using FlootyPermissions
using Dates
using UUIDs

struct WorkspaceFolder
    id::UUID
    path::String
    name::String
    added_at::DateTime
    added_by::UUID
    recursive::Bool
    readonly::Bool
    
    function WorkspaceFolder(path::String, name::String, added_by::UUID;
                            recursive::Bool=true, readonly::Bool=false)
        abs_path = abspath(path)
        isdir(abs_path) || error("Path is not a directory: $abs_path")
        new(uuid4(), abs_path, name, now(), added_by, recursive, readonly)
    end
end

function contains_path(folder::WorkspaceFolder, path::String)
    abs_path = abspath(path)
    if folder.recursive
        startswith(abs_path, folder.path)
    else
        dirname(abs_path) == folder.path
    end
end

function relative_path(folder::WorkspaceFolder, absolute_path::String)
    if startswith(absolute_path, folder.path)
        relpath(absolute_path, folder.path)
    else
        nothing
    end
end

mutable struct Workspace <: FlootyAbstract.AbstractWorkspace
    id::UUID
    name::String
    folders::Dict{UUID, WorkspaceFolder}
    folder_order::Vector{UUID}
    permissions::PermissionSet
    created_at::DateTime
    updated_at::DateTime
    created_by::UUID
    
    function Workspace(name::String, created_by::UUID; permissions::Union{PermissionSet, Nothing}=nothing)
        perms = permissions === nothing ? PermissionSet(created_by, :user) : permissions
        new(uuid4(), name, Dict{UUID, WorkspaceFolder}(), UUID[], perms, now(), now(), created_by)
    end
end

FlootyAbstract.workspace_id(ws::Workspace) = ws.id

function FlootyAbstract.workspace_folders(ws::Workspace)
    [ws.folders[id] for id in ws.folder_order if haskey(ws.folders, id)]
end

FlootyAbstract.workspace_permissions(ws::Workspace) = ws.permissions

function FlootyAbstract.add_folder_to_workspace!(ws::Workspace, path::String;
                                                name::String=basename(path),
                                                added_by::UUID=ws.created_by,
                                                recursive::Bool=true,
                                                readonly::Bool=false)
    folder = WorkspaceFolder(path, name, added_by; recursive=recursive, readonly=readonly)
    ws.folders[folder.id] = folder
    push!(ws.folder_order, folder.id)
    ws.updated_at = now()
    folder
end

function FlootyAbstract.remove_folder_from_workspace!(ws::Workspace, folder_id::UUID)
    haskey(ws.folders, folder_id) || return false
    delete!(ws.folders, folder_id)
    filter!(id -> id != folder_id, ws.folder_order)
    ws.updated_at = now()
    true
end

function FlootyAbstract.get_folder_from_workspace(ws::Workspace, folder_id::UUID)
    get(ws.folders, folder_id, nothing)
end

function find_folder_for_path(ws::Workspace, path::String)::Union{WorkspaceFolder, Nothing}
    abs_path = abspath(path)
    for folder in values(ws.folders)
        if contains_path(folder, abs_path)
            return folder
        end
    end
    nothing
end

function is_path_in_workspace(ws::Workspace, path::String)::Bool
    find_folder_for_path(ws, path) !== nothing
end

function resolve_path(ws::Workspace, relative_path::String)::Union{String, Nothing}
    # Check if path starts with a folder name
    parts = split(relative_path, "/")
    if length(parts) >= 1
        folder_name = parts[1]
        for folder in values(ws.folders)
            if folder.name == folder_name
                rest = join(parts[2:end], "/")
                candidate = joinpath(folder.path, rest)
                ispath(candidate) && return candidate
            end
        end
    end
    # Fallback: try direct resolution under each folder
    for folder in values(ws.folders)
        candidate = joinpath(folder.path, relative_path)
        ispath(candidate) && return candidate
    end
    nothing
end

export Workspace, WorkspaceFolder
export find_folder_for_path, is_path_in_workspace, resolve_path
export contains_path, relative_path

end # module FlootyWorkspaces

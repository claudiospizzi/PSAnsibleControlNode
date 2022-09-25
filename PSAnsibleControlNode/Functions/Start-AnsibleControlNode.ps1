<#
    .SYNOPSIS
        Start an ansilbe control node docker container.

    .DESCRIPTION
        This command is used to start a local docker container for the specific
        ansible repository. With this, an ansible control node under Windows is
        easy to use.

    .EXAMPLE
        PS C:\> Start-AnsibleControlNode
        Start the ansible control node with the current working directory.

    .EXAMPLE
        PS C:\> Start-AnsibleControlNode -RepositoryPath 'C:\Workspace\AnsibleRepo' -KeyPath 'C:\Workspace\AnsibleKeys'
        Start the ansible control node with custom repo and key path.

    .LINK
        https://github.com/claudiospizzi/PSAnsibleControlNode
#>
function Start-AnsibleControlNode
{
    [CmdletBinding()]
    param
    (
        # Path to the ansible repository. Defaults to the current workind directory.
        [Parameter(Mandatory = $false)]
        [System.String]
        $RepositoryPath = $PWD,

        # Path to the SSH key files. Defaults to the current user ~/.ssh path.
        [Parameter(Mandatory = $false)]
        [System.String]
        $KeyPath = "$HOME\.ssh",

        # Docker image to use. Defaults to the claudiospizzi/ansible-control-node image.
        [Parameter(Mandatory = $false)]
        [System.String]
        $ImageName = 'claudiospizzi/ansible-control-node',

        # Tag of the docker ansible-control-node image. Defaults to the latest.
        [Parameter(Mandatory = $false)]
        [System.String]
        $ImageTag = 'latest'
    )

    try
    {
        # Specify the additional paths
        $ansibleConfigPath = '{0}\ansible.cfg' -f $RepositoryPath.TrimEnd('\').TrimEnd('/')

        # Check the ansible repository
        if (-not (Test-Path -Path $RepositoryPath))
        {
            throw "The repository path was not found: $RepositoryPath"
        }
        if (-not (Test-Path -Path $ansibleConfigPath))
        {
            throw "The ansible config file was not found: $ansibleConfigPath"
        }

        # Check the SSH keys
        if (-not (Test-Path -Path $KeyPath))
        {
            throw "The SSH key path was not found: $KeyPath"
        }
        if ($null -eq (Get-ChildItem -Path $KeyPath -Filter 'id_*'))
        {
            throw 'No certificate files matching the wildcard pattern id_* found.'
        }

        # Check the docker desktop command
        if ($null -eq (Get-Command -Name 'docker.exe' -CommandType 'Application' -ErrorAction 'SilentlyContinue'))
        {
            throw 'The Docker executable docker.exe was not found in the path.'
        }
        if ($null -eq (Get-Process -Name 'Docker Desktop' -ErrorAction 'SilentlyContinue'))
        {
            throw 'The Docker Desktop process was not found. Start Docker Desktop.'
        }

        # Prepare the docker parameters
        $volumeKeys = '/{0}:/tmp/.ssh:ro' -f (Resolve-Path -Path $KeyPath).Path.Replace(':', '').Replace('\', '/').Trim('/')
        $volumeRepo = '/{0}:/ansible' -f (Resolve-Path -Path $RepositoryPath).Path.Replace(':', '').Replace('\', '/').Trim('/')
        $image      = '{0}:{1}' -f $ImageName, $ImageTag

        # Start the docker image
        docker.exe run -it --rm -v $volumeKeys -v $volumeRepo $image
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

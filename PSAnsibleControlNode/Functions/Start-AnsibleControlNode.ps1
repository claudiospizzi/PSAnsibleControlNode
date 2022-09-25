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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost')]
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
        $ImageTag = 'latest',

        # Hide the user information.
        [Parameter(Mandatory = $false)]
        [Switch]
        $Silent
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
        $RepositoryPath = (Resolve-Path -Path $RepositoryPath).Path

        # Check the SSH keys
        if (-not (Test-Path -Path $KeyPath))
        {
            throw "The SSH key path was not found: $KeyPath"
        }
        if ($null -eq (Get-ChildItem -Path $KeyPath -Filter 'id_*'))
        {
            throw 'No certificate files matching the wildcard pattern id_* found.'
        }
        $KeyPath = (Resolve-Path -Path $KeyPath).Path

        # Check the docker desktop command
        if ($null -eq (Get-Command -Name 'docker.exe' -CommandType 'Application' -ErrorAction 'SilentlyContinue'))
        {
            throw 'The Docker executable docker.exe was not found in the path.'
        }
        if ($null -eq (Get-Process -Name 'Docker Desktop' -ErrorAction 'SilentlyContinue'))
        {
            throw 'The Docker Desktop process was not found. Start Docker Desktop.'
        }

        # Ensure the helper files and folders exist
        $acnFolderName = '.ansible-control-node'
        if (-not (Test-Path -Path "$RepositoryPath\$acnFolderName" -PathType 'Container'))
        {
            New-Item -Path "$RepositoryPath\$acnFolderName" -ItemType 'Directory' -Force | Out-Null
        }
        if (-not (Test-Path -Path "$RepositoryPath\$acnFolderName\.bash_history" -PathType 'Leaf'))
        {
            New-Item -Path "$RepositoryPath\$acnFolderName\.bash_history" -ItemType 'File' -Force | Out-Null
        }

        # Prepare the docker parameters
        $normalizedKeyPath  = $KeyPath.Replace(':', '').Replace('\', '/').Trim('/')
        $normalizedRepoPath = $RepositoryPath.Replace(':', '').Replace('\', '/').Trim('/')
        $volumeKeys        = '/{0}:/tmp/.ssh:ro' -f $normalizedKeyPath
        $volumeBashHistory = '/{0}/{1}/.bash_history:/root/.bash_history' -f $normalizedRepoPath, $acnFolderName
        $volumeAnsibleRepo = '/{0}:/ansible' -f $normalizedRepoPath
        $image             = '{0}:{1}' -f $ImageName, $ImageTag

        # User information
        if (-not $Silent.IsPresent)
        {
            Write-Host ''
            Write-Host 'ANSIBLE CONTROL NODE'
            Write-Host '********************'
            Write-Host ''
            Write-Host "Ansible Repo: $RepositoryPath"
            Write-Host "SSH Key Path: $KeyPath"
            Write-Host "Docker Image: $image"
            Write-Host ''
        }

        # Start the docker image
        if ($PSCmdlet.ShouldProcess($image, 'Start Docker Container'))
        {
            docker.exe run -it --rm -v $volumeKeys -v $volumeBashHistory -v $volumeAnsibleRepo $image
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

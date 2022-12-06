<#
    .SYNOPSIS
        Start an ansible control node docker container.

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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'KeyPath')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param
    (
        # Path to the ansible repository. Defaults to the current working directory.
        [Parameter(Mandatory = $false)]
        [System.String]
        $RepositoryPath = $PWD,

        # Path to the SSH key files. Defaults to the current user ~/.ssh path.
        [Parameter(Mandatory = $false, ParameterSetName = 'KeyPath')]
        [System.String]
        $KeyPath = "$HOME\.ssh",

        # Id of the 1Password ssh key item. Check with `op.exe item list` for all items.
        [Parameter(Mandatory = $false, ParameterSetName = '1Password')]
        [Alias('1PasswordItemId')]
        [System.String]
        $OPItemId = '',

        # Optionally specify a different item label for the 1Password public key.
        [Parameter(Mandatory = $false, ParameterSetName = '1Password')]
        [Alias('1PasswordItemPublicKeyLabel')]
        [System.String]
        $OPItemPublicKeyLabel = 'public key',

        # Optionally specify a different item label for the 1Password private key.
        [Parameter(Mandatory = $false, ParameterSetName = '1Password')]
        [Alias('1PasswordItemPrivateKeyLabel')]
        [System.String]
        $OPItemPrivateKeyLabel = 'private key',

        # Optionally specify a different item label for the 1Password key type.
        [Parameter(Mandatory = $false, ParameterSetName = '1Password')]
        [Alias('1PasswordItemKeyTypeLabel')]
        [System.String]
        $OPItemKeyTypeLabel = 'key type',

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

        # Check the SSH keys specified by path
        if ($PSCmdlet.ParameterSetName -eq 'KeyPath')
        {
            if (-not (Test-Path -Path $KeyPath))
            {
                throw "The SSH key path was not found: $KeyPath"
            }
            if ($null -eq (Get-ChildItem -Path $KeyPath -Filter 'id_*'))
            {
                throw 'No certificate files matching the wildcard pattern id_* found.'
            }
            $KeyPath = (Resolve-Path -Path $KeyPath).Path
        }

        # Check the SSH keys specified by a 1Password item
        if ($PSCmdlet.ParameterSetName -eq '1Password')
        {
            # Ensure the command exists. Will throw an exception, if not.
            Get-Command -Name 'op.exe' | Out-Null

            $KeyPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (New-Guid)
            New-Item -Path $KeyPath -ItemType 'Directory' | Out-Null

            $keyItem = op.exe item get $OPItemId --fields "label=$OPItemPublicKeyLabel,label=$OPItemPrivateKeyLabel,label=$OPItemKeyTypeLabel" --format json | ConvertFrom-Json

            # Get the key type, used for the key file name.
            $keyType = $keyItem.Where({ $_.label -eq $OPItemKeyTypeLabel }).value

            Set-Content -Path "$KeyPath\id_$keyType.pub" -Value $keyItem.Where({ $_.label -eq $OPItemPublicKeyLabel }).value -Encoding 'UTF8'
            Set-Content -Path "$KeyPath\id_$keyType" -Value $keyItem.Where({ $_.label -eq $OPItemPrivateKeyLabel }).value -Encoding 'UTF8'
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
            Write-Host "SSH Key Path: $KeyPath$(if ($PSCmdlet.ParameterSetName -eq '1Password') { '   (removed in 10 sec)' })"
            Write-Host "Docker Image: $image"
            Write-Host ''
        }

        # Start the docker image
        if ($PSCmdlet.ShouldProcess($image, 'Start Docker Container'))
        {
            # Remove the 1Password key files after 10 seconds
            if ($PSCmdlet.ParameterSetName -eq '1Password')
            {
                Start-Job -ScriptBlock {
                    Start-Sleep -Seconds 10
                    Remove-Item -Path $using:KeyPath -Force -Recurse
                } | Out-Null
            }

            docker.exe run -it --rm -v $volumeKeys -v $volumeBashHistory -v $volumeAnsibleRepo $image
        }
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError($_)
    }
    finally
    {
        # Remove the 1Password key files after closing the docker instance
        if ($PSCmdlet.ParameterSetName -eq '1Password' -and (Test-Path -Path $KeyPath))
        {
            Remove-Item -Path $KeyPath -Force -Recurse
        }
    }
}

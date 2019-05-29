$DataFullNames = "
Adam Jan-Kowalski
Jon Snow-White
"

$DataEmials = "
Tomasz Dab <tdab@testxyz.co.uk>
"

$DataLogins = "
jsnowthesecond
"

$Domain = 'testxyz.co.uk'
$MailPattern = '@{0}' -f $Domain

$ComputerLastLoginDate = (Get-Date).AddMonths(-3)
$OUs = @('OU=Desktops,OU=Workstations,OU=Computers - PL,DC=testxyz,DC=co,DC=uk', 'OU=Laptops,OU=Workstations,OU=Computers - PL,DC=testxyz,DC=co,DC=uk', 'OU=Workstations,OU=Computers - UK,DC=testxyz,DC=co,DC=uk')

$DataMails = foreach ($item in $DataEmials) {
    if ($item -match "-") {
        (Select-String -InputObject $item -Pattern '\w+\-\w+@\w+\.\w+.\w+' -AllMatches).Matches.Value
    } else {
        (Select-String -InputObject $item -Pattern '\w+@\w+\.\w+.\w+' -AllMatches).Matches.Value
    }
}
$LoginsFromMails = $DataMails.Replace($MailPattern, '')

$DataFromMails = foreach ($item in $LoginsFromMails) {
    [PSCustomObject]@{
        Login  = $item
        Source = 'Mail'
    }
}

$DataFromNamesTemp = $DataFullNames | ConvertFrom-Csv -Header 'Name'

$DataFromNames = foreach ($item in $DataFromNamesTemp) {
    $ItemName = $item.Name
    [PSCustomObject]@{
        Login = (Get-ADUser -Filter {
                Name -eq $ItemName
            }).SamAccountName
        Source = 'FullName'
    }
}


$DataFromLoginsTemp = $DataLogins | ConvertFrom-Csv -Header 'SamAccountName'
$DataFromLogins = foreach ($item in $DataFromLoginsTemp) {
    [PSCustomObject]@{
        Login = $item.SamAccountName
        Source = 'Login'
    }
}

$AllItems = ($DataFromNames, $DataFromMails, $DataFromLogins | ForEach-Object {
        $_
    })

$AllProbablyLogins = foreach ($item in $AllItems) {
    if ($item.Login -match '-') {
        [PSCustomObject]@{
            Login = $item.Login.Split('-')[0]
            Source = $item.Source
        }
        [PSCustomObject]@{
            Login = $item.Login.Split('-')[1]
            Source = $item.Source
        }
    }
}

$ComputerNameAll = foreach ($OU in $OUs) {
    Get-ADComputer -Filter * -SearchBase $OU -Properties LastLogonDate, OperatingSystem | Where-Object -FilterScript {
        $_.lastlogonDate -gt $ComputerLastLoginDate -and $_.enabled -and ($_.DNSHostName -match $domain)
    }
}

$ComputerDataFromLogins = $AllItems | Where-Object {
    $_.Login
} | ForEach-Object {
    $LoginMain = $_.Login
    $ComputerData = $null
    $UserADInfo = Get-ADUser -Filter {
        SamAccountName -eq $LoginMain
    }
    
    if ($LoginMain -match '-') {
        $Logins = $_.Login.Split('-')
        foreach ($Login in $Logins) {
            if ($Login.Length -gt 13) {
                $Login = $Login.Substring(0, 13)
                $ComputerData = $ComputerNameAll | Where-Object {
                    $_.Name -match $Login
                }
                
                $AdditionaData = "DoubleName and > 13"
                
            } else {
                $ComputerData = $ComputerNameAll | Where-Object {
                    $_.Name -match $Login
                }
                
                $AdditionaData = 'DoubleName'
                
            }
            [PSCustomObject]@{
                Computer = $ComputerData.Name -join ', '
                Login    = $LoginMain
                LoginPart = $Login
                Name     = $UserADInfo.Name
                Mail     = $UserADInfo.UserPrincipalName
                SoftwareExcluded = $_.Source
                ComputerOS = $ComputerData.OperatingSystem -join ', '
                AdditionaData = $AdditionaData
            }
        }
    } else {
        if ($LoginMain.Length -gt 13) {
            $Login = $LoginMain.Substring(0, 13)
            $ComputerData = $ComputerNameAll | Where-Object {
                $_.Name -match $Login
            }
            $AdditionaData = '>13'
        } else {
            $Login = $LoginMain
            if ($UserADInfo.SamAccountName -eq $Login) {
                $ComputerData = $ComputerNameAll | Where-Object {
                    $_.Name -match $Login
                }
                $AdditionaData = ''
            } else {
                $AdditionaData = 'Login is different than in ActiveDirectory'
            }
            
        }
        [PSCustomObject]@{
            Computer = $ComputerData.Name -join ', '
            Login    = $LoginMain
            LoginPart = $Login
            Name     = $UserADInfo.Name
            Mail     = $UserADInfo.UserPrincipalName
            SoftwareExcluded = $_.Source
            ComputerOS = $ComputerData.OperatingSystem -join ', '
            AdditionaData = $AdditionaData
        }
    }
}

'{0}+{1}+{2} ?= {3}' -f ($DataFromNames | Measure-Object).Count, ($DataFromMails | Measure-Object).Count, ($DataFromLogins | Measure-Object).Count, ($ComputerDataFromLogins | Where-Object {
        $_.Computer
    }).Count

"All searched conditions"
$Script:i = 0
$ComputerDataFromLogins | Sort-Object Login | Select-Object @{
    Name        = 'No.'; Expression = {
        $Script:i++; $Script:i
    }
}, * | Format-Table -AutoSize

"Objects with Computer Name only"
$Script:i = 0
$ComputerDataFromLogins | Where-Object {
    $_.Computer
} | Sort-Object Login | Select-Object @{
    Name        = 'No.'; Expression = {
        $Script:i++; $Script:i
    }
}, * | Format-Table -AutoSize

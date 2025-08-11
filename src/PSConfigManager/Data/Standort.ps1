
$Script:Standort = [Ordered]@{
    AT = [Ordered]@{
        Firma             = 'Kostwein Maschinenbau GmbH'
        Country           = [Ordered]@{
            c           = 'AT'
            co          = 'Österreich'
            Country     = 'Austria'
            countrycode = 40
        }
        Bundesland        = 'Carinthia'
        State             = 'Kärnten'
        PreferredLanguage = 'de-AT'
        Branches          = [Ordered]@{
            KL = [Ordered]@{
                Prefix        = 'ATKL'
                City          = 'Klagenfurt'
                PostalCode    = '9020'
                StreetAddress = 'Berthold-Schwarz-Straße 51'
                Werk          = @()
                Kostenstelle  = 0
            }
            ZL = [Ordered]@{
                Prefix        = 'ATZL'
                City          = 'Klagenfurt'
                PostalCode    = '9020'
                StreetAddress = 'Fallegasse 3'
                Werk          = @()
                Kostenstelle  = 0
            }
            MS = [Ordered]@{
                Prefix        = 'ATMS'
                City          = 'Maria Saal'
                PostalCode    = '9063'
                StreetAddress = 'Ratzendorf 2A'
                Werk          = @()
                Kostenstelle  = 0
            }
            VK = [Ordered]@{
                Prefix        = 'ATVK'
                City          = 'Völkermarkt'
                PostalCode    = '9100'
                StreetAddress = 'Petzenweg 7'
                Werk          = @()
                Kostenstelle  = 0
            }
            UB = [Ordered]@{
                Prefix        = 'ATUB'
                City          = 'Unterbergen'
                PostalCode    = '9163'
                StreetAddress = 'Unterbergen 24'
                Werk          = @()
                Kostenstelle  = 0
            }
            SV = [Ordered]@{
                Prefix        = 'ATSV'
                City          = 'St.Veit'
                PostalCode    = '9300'
                StreetAddress = 'Industrieparkstraße 1'
                Werk          = @()
                Kostenstelle  = 0
            }
        }
    }
    HR = [Ordered]@{
        Firma             = 'Kostwein Proizvodnja Strojeva d.o.o.'
        Country           = [Ordered]@{
            c           = 'HR'
            co          = 'Kroatien'
            Country     = 'Croatia'
            countrycode = 191
        }
        Bundesland        = 'Gespanschaft Varaždin'
        State             = 'Varaždin County'
        PreferredLanguage = 'hr-HR'
        Branches          = [Ordered]@{
            TR = [Ordered]@{
                Prefix        = 'HRTR'
                City          = 'Varazdin'
                PostalCode    = '42000'
                StreetAddress = 'Podravska ulica 37'
                Werk          = @(3, 13)
                Kostenstelle  = 33
            }
            VA = [Ordered]@{
                Prefix        = 'HRVA'
                City          = 'Varazdin'
                PostalCode    = '42202'
                StreetAddress = 'Gospodarska 11'
                Werk          = @()
                Kostenstelle  = 0
            }
        }
    }
    IN = [Ordered]@{
        Firma             = 'Kostwein India Company Private Ltd'
        Country           = [Ordered]@{
            c           = 'IN'
            co          = 'Indien'
            Country     = 'India'
            countrycode = 356
        }
        Bundesland        = 'Gujarat'
        State             = 'Gujarat'
        PreferredLanguage = 'hi-IN'
        Branches          = [Ordered]@{
            AB = [Ordered]@{
                Prefix        = 'INAB'
                City          = 'Ahmedabad'
                PostalCode    = '382405'
                StreetAddress = 'Plot N0. 170, N.I D.C. Industrial Estate'
                Werk          = @(15, 17)
                Kostenstelle  = 80000
            }
        }
    }
    IT = [Ordered]@{
        Firma             = 'Kostwein Metalinox S.r.l.'
        Country           = [Ordered]@{
            c           = 'IT'
            co          = 'Italien'
            Country     = 'Italy'
            countrycode = 380
        }
        Bundesland        = 'Friuli-Venezia Giulia'
        State             = 'Friuli Venezia Giulia'
        PreferredLanguage = 'it-IT'
        Branches          = [Ordered]@{
            UD = [Ordered]@{
                Prefix        = 'ITUD'
                City          = 'Fiumicello Villa Vicentina'
                PostalCode    = '33059'
                StreetAddress = 'Via Cortona, 13'
                Werk          = @(50, 52)
                Kostenstelle  = 50000
            }
        }
    }
    US = [Ordered]@{
        Firma             = 'Kostwein Corporation'
        Country           = [Ordered]@{
            c           = 'US'
            co          = 'USA'
            Country     = 'America'
            countrycode = 840
        }
        Bundesland        = 'South Carolina'
        State             = 'South Carolina'
        PreferredLanguage = 'en-US'
        Branches          = [Ordered]@{
            GR = [Ordered]@{
                Prefix        = 'USGR'
                City          = 'Greenville'
                PostalCode    = 'SC29615'
                StreetAddress = '500 Hartness Dr'
                Werk          = @()
                Kostenstelle  = 0
            }
        }
    }
}

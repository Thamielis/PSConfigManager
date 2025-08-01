
class LinearMap {
    [object[]]$Items

    LinearMap() {
        $this.Items = @()
    }

    [void] Add([object]$k, [object]$v) {
        # Fügt ein Key-Value-Paar hinzu
        $this.Items += [PSCustomObject]@{Key = $k; Value = $v }
    }

    [object] Get([object]$k) {
        foreach ($item in $this.Items) {
            if ($item.Key -eq $k) {
                return $item.Value
            }
        }
        throw [System.Collections.Generic.KeyNotFoundException]::new("Key not found: $k")
    }
}

class BetterMap {
    [LinearMap[]]$Maps

    BetterMap([int]$n) {
        $this.Maps = @(
            for ($i = 0; $i -lt $n; $i++) {
                [LinearMap]::new()
            }
        )
    }

    [LinearMap] FindMap([object]$k) {
        # Benutze GetHashCode(), Ergebnis kann negativ sein, daher [Math]::Abs
        $index = [Math]::Abs($k.GetHashCode()) % $this.Maps.Count

        return $this.Maps[$index]
    }

    [void] Add([object]$k, [object]$v) {
        $this.FindMap($k).Add($k, $v)
    }

    [object] Get([object]$k) {
        return $this.FindMap($k).Get($k)
    }
}

class HashMap {
    [BetterMap]$Maps
    [int]$Num

    HashMap() {
        $this.Maps = [BetterMap]::new(2)
        $this.Num = 0
    }

    [object] Get([object]$k) {
        return $this.Maps.Get($k)
    }

    [void] Add([object]$k, [object]$v) {
        if ($this.Num -eq $this.Maps.Maps.Count) {
            $this.Resize()
        }
        $this.Maps.Add($k, $v)
        $this.Num += 1
    }

    [void] Resize() {
        $newMap = [BetterMap]::new($this.Num * 2)
        foreach ($m in $this.Maps.Maps) {
            foreach ($item in $m.Items) {
                $newMap.Add($item.Key, $item.Value)
            }
        }
        $this.Maps = $newMap
    }
}

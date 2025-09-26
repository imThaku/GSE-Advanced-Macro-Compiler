# Variables Dynamiques GSE

## Introduction

Le système de variables dynamiques permet d'évaluer les variables au moment de l'exécution de la séquence (quand vous appuyez sur la touche) plutôt qu'au moment de la compilation. Cela permet de créer des macros qui s'adaptent en temps réel à l'état du jeu.

## Activation

Les variables dynamiques sont **désactivées par défaut** pour maintenir la compatibilité avec les séquences existantes.

### Activation globale
```lua
-- Activer les variables dynamiques pour toutes les nouvelles séquences
GSEOptions.useDynamicVariables = true

-- Ou utiliser la fonction helper
GSE.SetSequenceDynamicVariables("MonMacro", true)
```

### Test de fonctionnement
```lua
-- Tester le système de variables dynamiques
/run GSE.TestDynamicVariables()
```

## Utilisation

### Syntaxe
Les variables dynamiques utilisent la même syntaxe que les variables statiques : `=expression`

### Exemples d'utilisation

#### 1. Spell adaptatif selon la cible
```lua
-- Dans une action, vous pouvez utiliser :
spell = "=UnitExists('target') and 'Frostbolt' or 'Arcane Intellect'"
```
Cette expression évaluera à chaque clic :
- "Frostbolt" si vous avez une cible
- "Arcane Intellect" si vous n'avez pas de cible

#### 2. Actions conditionnelles selon les HP
```lua
spell = "=UnitHealthMax('player') - UnitHealth('player') > 10000 and 'Heal' or 'Smite'"
```
Utilise "Heal" si il vous manque plus de 10000 HP, sinon "Smite".

#### 3. Rotation selon les buffs
```lua
spell = "=UnitBuff('player', 'Bloodlust') and 'Pyroblast' or 'Fireball'"
```

#### 4. Macro texte dynamique
```lua
macrotext = "=/cast =UnitInRaid('player') and '[group:raid] ' or '[group:party] '..GetSpellInfo(12345)"
```

## Différences avec les variables statiques

| Variables Statiques | Variables Dynamiques |
|-------------------|---------------------|
| Évaluées à la compilation | Évaluées à chaque clic |
| Valeur fixe pendant la session | Valeur recalculée en temps réel |
| Performance optimale | Légère surcharge de calcul |
| Compatibilité garantie | Nécessite activation explicite |

## Optimisations

Le système inclut plusieurs optimisations :

1. **Cache avec timestamp** : Les résultats sont mis en cache pendant 100ms
2. **Gestion d'erreurs** : Les erreurs n'interrompent pas l'exécution
3. **Fallback automatique** : Utilise la valeur statique en cas d'erreur

## Cache et Performance

```lua
-- Vider le cache manuellement si nécessaire
GSE.ClearDynamicVariableCache()

-- Évaluer sans cache (pour le debug)
local result = GSE.EvaluateVariableDynamically("math.random()", false)
```

## Blocs IF Dynamiques

**Nouveauté** : Les blocs IF de GSE peuvent maintenant être évalués dynamiquement !

### Comment ça marche
Quand les variables dynamiques sont activées, les blocs IF réévaluent leur condition **à chaque clic** au lieu d'une seule fois à la compilation.

### Exemple d'utilisation
```
Bloc IF avec condition: =GSE.V.Afflicted()
├─ TRUE: Action avec spell="Obliterate"
└─ FALSE: Action avec spell="Frost Strike"
```

À chaque clic, la condition `GSE.V.Afflicted()` sera réévaluée et la bonne branche sera exécutée.

### Migration depuis les blocs IF statiques
Aucune modification nécessaire ! Vos blocs IF existants fonctionneront automatiquement en mode dynamique une fois les variables dynamiques activées.

## Cas d'utilisation avancés

### 1. Healing intelligent
```lua
-- Priorité de heal basée sur les HP des membres du groupe
spell = "=
local lowest = nil
local lowestHP = 1
for i=1,5 do
  local unit = 'party'..i
  if UnitExists(unit) then
    local hp = UnitHealth(unit) / UnitHealthMax(unit)
    if hp < lowestHP then
      lowestHP = hp
      lowest = unit
    end
  end
end
return lowest and 'Heal' or 'Smite'
"
```

### 2. Rotation avec cooldowns
```lua
spell = "=
local spell1CD = GetSpellCooldown('Fireball')
local spell2CD = GetSpellCooldown('Frostbolt')
return spell1CD == 0 and 'Fireball' or (spell2CD == 0 and 'Frostbolt' or 'Arcane Missiles')
"
```

## Compatibilité

- ✅ **Compatible** avec toutes les séquences existantes (quand désactivé)
- ✅ **Compatible** avec les variables GSE existantes
- ✅ **Compatible** avec les modes Multiclick et standard
- ⚠️ **Attention** : Nécessite une recompilation des séquences après activation

## Debugging

Utilisez ces fonctions pour diagnostiquer les problèmes :

```lua
-- Activer le debug des variables
GSEOptions.debug = true
GSEOptions.DebugModules["API"] = true

-- Tester une expression spécifique
/run print(GSE.EvaluateVariableDynamically("UnitName('player')", nil))
```

## Migration

Pour convertir une séquence existante :

1. Activer les variables dynamiques
2. Recompiler la séquence (elle se recharge automatiquement)
3. Tester le comportement
4. Ajuster les expressions si nécessaire

---

**Note** : Cette fonctionnalité est expérimentale. Testez soigneusement vos macros avant utilisation en raid ou PvP.
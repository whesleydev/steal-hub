# steal-hub

Hub do Steal A Brainrot. Dois links, mesma base de codigo.

## Link fixo

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/whesleydev/steal-hub/main/stealbrainrot.lua"))()
```

Versao estavel. O botao **Verificar atualizacao** dentro do hub puxa a nova sem relogar.

## Link de teste (temporario)

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/whesleydev/steal-hub/test/stealbrainrot.lua"))()
```

Branch `test`. Pode quebrar. Quando estabiliza, vai para `main`.

## Arquivos

| arquivo | papel |
|---|---|
| `stealbrainrot.lua` | script principal |
| `version.txt` | versao atual, lida pelo botao de atualizacao |
| `README.md` | este arquivo |

## Publicar uma versao nova

1. sobe o `SCRIPT_VERSION` dentro de `stealbrainrot.lua`
2. sobe `version.txt` com o mesmo numero
3. quem estiver com o hub aberto clica em **Verificar atualizacao**

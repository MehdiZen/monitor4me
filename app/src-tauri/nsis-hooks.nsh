; nsis-hooks.nsh -- Hooks personnalises pour l'installeur monitor4me
; Execute par le template NSIS de Tauri 2 via installerHooks

; Rien de special a l'installation
!macro NSIS_HOOK_PREINSTALL
!macroend

!macro NSIS_HOOK_POSTINSTALL
!macroend

; Rien de special avant la desinstallation
!macro NSIS_HOOK_PREUNINSTALL
!macroend

; Nettoyage complet apres desinstallation
!macro NSIS_HOOK_POSTUNINSTALL
  ; Supprimer la variable d'environnement INFLUX_TOKEN (systeme + utilisateur)
  DeleteRegValue HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "INFLUX_TOKEN"
  DeleteRegValue HKCU "Environment" "INFLUX_TOKEN"
  ; Notifier Windows du changement d'environnement
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000

  ; Supprimer les donnees WebView (localStorage, cookies, cache)
  RMDir /r "$LOCALAPPDATA\dev.monitor4me.dashboard"

  ; Supprimer les donnees applicatives (collector, config)
  RMDir /r "$APPDATA\monitor4me"

  ; Supprimer les fichiers temporaires du wizard
  Delete "$TEMP\monitor4me-setup.log"
  Delete "$TEMP\monitor4me-launcher.ps1"
!macroend

(define-module (dwl-guile home-service)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (gnu packages)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages freedesktop)
  #:use-module ((gnu packages linux) #:select(procps))
  #:use-module ((gnu packages admin) #:select(shepherd))
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu services configuration)
  #:use-module (dwl-guile utils)
  #:use-module (dwl-guile patches)
  #:use-module (dwl-guile packages)
  #:use-module (dwl-guile serializer)
  #:export (
            home-dwl-guile-service-type
            home-dwl-guile-configuration
            home-dwl-guile-configuration?
            <home-dwl-guile-configuration>
            home-dwl-guile-configuration-config
            home-dwl-guile-configuration-package
            home-dwl-guile-configuration-native-qt?
            home-dwl-guile-configuration-auto-start?
            home-dwl-guile-configuration-reload-config-on-change?
            home-dwl-guile-configuration-startup-command
            home-dwl-guile-configuration-environment-variables
            %dwl-guile-base-env-variables)

  ;; re-export configurations so that they are
  ;; available in the home environment without
  ;; having to manually import them.
  #:re-export (dwl-guile patch-dwl-guile-package))

;; Base wayland environment variables
;; TODO: Add support for using electron apps natively in wayland?
(define %dwl-guile-base-env-variables
  `(("XDG_CURRENT_DESKTOP" . "dwl")
    ("XDG_SESSION_TYPE" . "wayland")
    ("MOZ_ENABLE_WAYLAND" . "1")
    ("ELM_ENGINE" . "wayland_egl")
    ("ECORE_EVAS_ENGINE" . "wayland-egl")
    ("_JAVA_AWT_WM_NONREPARENTING" . "1")
    ("GDK_BACKEND" . "wayland")))

;; dwl service type configuration
(define-configuration
  home-dwl-guile-configuration
  (package
   (package dwl-guile)
   "The dwl package to use.
    If you want to use a custom dwl package, set @code{(package-transform #f)}
    in your dwl-guile configuration.")
  (auto-start?
   (boolean #t)
   "Launch dwl automatically upon user login. Defaults to #t.")
  (reload-config-on-change?
   (boolean #t)
   "Automatically reload dwl-guile configuration when reconfiguring the home environment.")
  (environment-variables
   (list %dwl-guile-base-env-variables)
   "Environment variables for enabling Wayland support in many different applications.
    Basic environment variables will be added if no value is specified.

    You can modify the variables that will be set by extending
    @code{%dwl-guile-base-env-variables}, or by specifying a custom list.")
  (native-qt?
   (boolean #t)
   "If Qt applications should be rendered natively in Wayland.
This will also install the qtwayland package.")
  (startup-command
   (maybe-string #f)
   "A command to execute on dwl-guile startup. The command will be passed
to the '-s' parameter of dwl-guile.")
  (config
   (sexp-config '())
   "Custom dwl-guile configuration. Replaces config.h.")
  (no-serialization))

(define (home-dwl-guile-environment-variables-service config)
  (append
   (home-dwl-guile-configuration-environment-variables config)
   (if (home-dwl-guile-configuration-native-qt? config)
       `(("QT_QPA_PLATFORM" . "wayland-egl"))
       '())))

(define (home-dwl-guile-profile-service config)
  (append
   (list (home-dwl-guile-configuration-package config)
         xdg-desktop-portal
         xdg-desktop-portal-wlr)
   (if (home-dwl-guile-configuration-native-qt? config)
       (list qtwayland)
       '())))

(define (home-dwl-guile-shepherd-service config)
  "Return a <shepherd-service> for the dwl-guile service"
  (list
   (shepherd-service
    (documentation "Run dwl-guile.")
    (provision '(dwl-guile))
    (auto-start? (home-dwl-guile-configuration-auto-start? config))
    (start
     (let* ((config-dir (string-append (getenv "HOME") "/.config/dwl-guile"))
            (startup-command (home-dwl-guile-configuration-startup-command config)))
       #~(make-forkexec-constructor
          (list
           #$@(append
               (list (file-append (home-dwl-guile-configuration-package config) "/bin/dwl-guile")
                     "-c" (string-append config-dir "/config.scm"))
               (if startup-command (list "-s" startup-command) '())))
          #:pid-file #$(string-append (or (getenv "XDG_RUNTIME_DIR")
                                          (format #f "/run/user/~a" (getuid)))
                                      "/dwl-guile.pid")
          #:log-file #$(format #f "~a/log/dwl-guile.log"
                           (or (getenv "XDG_STATE_HOME")
                               (format #f "~a/.local/state"
                                       (getenv "HOME")))))))
    (stop #~(make-kill-destructor)))))

(define (home-dwl-guile-on-change-service config)
  (if (home-dwl-guile-configuration-reload-config-on-change? config)
      `(("files/.config/dwl-guile/config.scm"
         ,#~(system* #$(file-append (home-dwl-guile-configuration-package config)
                                    "/bin/dwl-guile")
                     "-e" "(dwl:reload-config)")))
      '()))

(define (home-dwl-guile-xdg-configuration-files-service config)
  `(("dwl-guile/config.scm"
     ,(mixed-text-file
       "dwl-guile.scm"
       (serialize-sexp-config #f (home-dwl-guile-configuration-config config))))))

(define (home-dwl-guile-extensions original-config extensions)
  (let ((extensions (reverse extensions)))
    (home-dwl-guile-configuration
     (inherit original-config)
     (config
      (fold append '()
            (append extensions
                    (home-dwl-guile-configuration-config original-config)))))))

(define home-dwl-guile-service-type
  (service-type
   (name 'home-dwl-guile)
   (extensions
    (list
     (service-extension
      home-profile-service-type
      home-dwl-guile-profile-service)
     (service-extension
      home-environment-variables-service-type
      home-dwl-guile-environment-variables-service)
     (service-extension
      home-xdg-configuration-files-service-type
      home-dwl-guile-xdg-configuration-files-service)
     (service-extension
      home-shepherd-service-type
      home-dwl-guile-shepherd-service)
     (service-extension
      home-run-on-change-service-type
      home-dwl-guile-on-change-service)))
   (compose identity)
   (extend home-dwl-guile-extensions)
   (default-value (home-dwl-guile-configuration))
   (description "Configure and install dwl-guile")))

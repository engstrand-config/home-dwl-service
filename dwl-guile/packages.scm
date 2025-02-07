(define-module (dwl-guile packages)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages libffi)
  #:use-module (gnu packages libbsd)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages pciutils)
  #:use-module (gnu packages build-tools)
  #:use-module (gnu packages freedesktop)
  #:use-module (dwl-guile patches)
  #:export (
            dwl-guile
            patch-dwl-guile-package))


(define dwl-guile
  (package
    (inherit dwl)
    (name "dwl-guile")
    (version "2.0.2")
    (inputs
     (modify-inputs (package-inputs dwl)
                    (prepend guile-3.0)
                    (replace "wlroots" wlroots-0.16)))
    (source
     (origin
       (inherit (package-source dwl))
       (uri (git-reference
             (url "https://github.com/engstrand-config/dwl-guile")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0z8ls92cgkry0fvybqzvg8jplwh3zjakdmq79kfxbczabvyijxk8"))))))

(define* (patch-dwl-guile-package pkg #:key (patches '()))
  "Create a new patched package of PKG with each patch in PATCHES
applied. This can be used to dynamically apply patches imported from
@code{(dwl-guile patches)}. Generally, it is recommended to create your
own package for dwl-guile that already has the patches applied."
  (package
   (inherit pkg)
   (source
    (origin
     (inherit (package-source pkg))
     (patch-flags '("-p1" "-F3"))
     (patches patches)))))

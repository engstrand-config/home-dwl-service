(define-module (dwl-guile configuration transform)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (ice-9 exceptions)
  #:use-module (gnu system keyboard)
  #:use-module (guix gexp)
  #:use-module (dwl-guile utils)
  #:use-module (dwl-guile configuration)
  #:use-module (dwl-guile configuration keycodes)
  #:export (
            arrange->exp
            binding->exp
            kbd->modifiers-and-keycode
            dwl-config->alist
            configuration->alist))

;; Converts an arrange procedure into a scheme expression.
(define (arrange->exp proc)
  (if
   (not proc)
   proc
   `(. (lambda (monitor) ,proc))))

;; Converts a binding procedure into a scheme expression.
(define (binding->exp proc)
  (if
   (not proc)
   proc
   `(. (lambda () ,proc))))

;; Converts a kbd key sequence into an alist containing
;; a list of modifiers and a keycode.
;;
;; TODO: Support more modifiers?
(define (kbd->modifiers-and-keycode str field)
  (define (parse-modifiers mods)
    (map (lambda (m)
           (match m
             ("C" 'CTRL)
             ("M" 'ALT)
             ("S" 'SHIFT)
             ("s" 'SUPER)
             (_ (raise-exception
                 (make-exception-with-message
                  (string-append "dwl: '" m "' is not a valid modifier"))))))
         mods))

  (define (parse-key key)
    (let ((first (string-take key 1)))
      (if (equal? first "[")
          (string->number (string-trim-both key (char-set #\[ #\])))
          (string->keycode key))))

  (define (parse-kbd mods k)
    `(("modifiers" . ,(parse-modifiers mods))
      (,field . ,(parse-key k))))

  (define (parse-kbd-without-keysym str)
    (let ((params (string-split str #\-)))
      (match params
        ((k) (parse-kbd '() k))
        ((mods ... k) (parse-kbd mods k))
        (_ (raise-exception
            (make-exception-with-message
             (string-append "dwl: '" str "' is not a valid key sequence")))))))

  (define (parse-kbd-with-keysym str index)
    (if (eq? index 0)
        (parse-kbd '() str)
        (let ((target-index (- index 1)))
          (parse-kbd (string-split (string-take str target-index) #\-)
                     (substring str index)))))

  (let ((keysym-index (string-contains str "<")))
    (if (eq? keysym-index #f)
        (parse-kbd-without-keysym str)
        (parse-kbd-with-keysym str keysym-index))))

;; Converts a configuration into alist to allow the values to easily be
;; fetched in C using `scm_assoc_ref(alist, key)`.
(define*
  (configuration->alist
   #:key
   (transform-value #f)
   (type #f)
   (config '())
   (source '()))
  (remove
   ;; the %location field is autogenerated and is not needed
   (lambda (pair) (equal? (car pair) "%location"))
   (fold-right
    (lambda (field acc)
      (append
       (let* ((value ((record-accessor type field) config))
              (transformed (if (not transform-value)
                               value
                               (transform-value field value source)))
              (field (remove-question-mark (symbol->string field))))
         (if (or (equal? field "key") (equal? field "button"))
             transformed
             `((,field . ,transformed))))
       acc))
    '()
    (record-type-fields type))))

(define (transform-rule field value source)
  (match
      field
    ('tag
     (let ((tags (length (dwl-config-tags source)))
           (tag (if (eq? value 0) value (- value 1))))
       (if
        (< tag tags)
        tag
        (raise-exception
         (make-exception-with-message
          (string-append
           "dwl: specified tag '"
           (number->string value)
           "' is out of bounds, there are only "
           (number->string tags)
           " available tags"))))))
    (_ value)))

(define (transform-layout field value source)
  (match
      field
    ('arrange (arrange->exp value))
    (_ value)))

(define (transform-key field value source)
  (match
      field
    ('action (binding->exp value))
    ('key (kbd->modifiers-and-keycode value "key"))
    (_ value)))

(define (transform-button field value source)
  (match
      field
    ('action (binding->exp value))
    ('key (kbd->modifiers-and-keycode value "button"))
    (_ value)))

(define (transform-xkb-rule field value source)
  (match
      field
    ((or 'layouts 'variants 'options)
     (if
      (null? value)
      "" ;; empty string is interpreted as NULL in `xkb_keymap_new_from_names()`
      (string-join value ",")))
    (_ value)))

(define (transform-monitor-rule field value source)
  (match
      field
    ('layout
     (let* ((layouts (dwl-config-layouts source))
            (index (list-index (lambda (l) (equal? (dwl-layout-id l) value)) layouts)))
       (match
           index
         (#f
          (raise-exception
           (make-exception-with-message
            (string-append "dwl: '" value "' is not a valid layout id"))))
         (_ index))))
    (_ value)))

(define (transform-config field value source)
  (match
      field
    ('colors (dwl-colors->alist value source))
    ((or 'keys 'tty-keys) (map (lambda (key) (dwl-key->alist key source)) value))
    ('buttons (map (lambda (button) (dwl-button->alist button source)) value))
    ('layouts (map (lambda (layout) (dwl-layout->alist layout source)) value))
    ('rules (map (lambda (rule) (dwl-rule->alist rule source)) value))
    ('monitor-rules (map (lambda (rule) (dwl-monitor-rule->alist rule source)) value))
    ('xkb-rules (if (not value) value (dwl-xkb-rule->alist value source)))
    ('tag-keys
     (if (<= (length (dwl-config-tags source)) (length (dwl-tag-keys-keys value)))
         (dwl-tag-keys->alist value source)
         (raise-exception
          (make-exception-with-message
           "dwl: too few tag keys, not all tags can be accessed"))))
    (_ value)))

(define (dwl-colors->alist colors source)
  (configuration->alist
   #:type <dwl-colors>
   #:config colors
   #:source source))

(define (dwl-rule->alist rule source)
  (configuration->alist
   #:transform-value transform-rule
   #:type <dwl-rule>
   #:config rule
   #:source source))

(define (dwl-layout->alist layout source)
  (configuration->alist
   #:type <dwl-layout>
   #:transform-value transform-layout
   #:config layout
   #:source source))

(define (dwl-key->alist key source)
  (configuration->alist
   #:transform-value transform-key
   #:type <dwl-key>
   #:config key
   #:source source))

(define (dwl-button->alist button source)
  (configuration->alist
   #:transform-value transform-button
   #:type <dwl-button>
   #:config button
   #:source source))

;; Transform tag keys into separate dwl-key configurations.
;; This is a helper transform for generating keybindings for tag actions,
;; e.g. viewing tags, moving windows, toggling visibilty of tags, etc.
;; For example, a list of 9 tags will result i 9*4 keybindings.
;;
;; TODO: Add correct action to each generated keybinding
;; TODO: Do we need to specify different bindings for those that use the shift modifier?
;;       See https://github.com/djpohly/dwl/blob/3b05eadeaf5e2de4caf127cfa07642342cccddbc/config.def.h#L55
(define (dwl-tag-keys->alist value source)
  (let ((keys (dwl-tag-keys-keys value))
        (view-modifiers (dwl-tag-keys-view-modifiers value))
        (tag-modifiers (dwl-tag-keys-tag-modifiers value))
        (toggle-view-modifiers (dwl-tag-keys-toggle-view-modifiers value))
        (toggle-tag-modifiers (dwl-tag-keys-toggle-tag-modifiers value)))
    (map
     (lambda (parsed-key) (dwl-key->alist parsed-key source))
     (fold
      (lambda (pair acc)
        (let ((key (car pair))
              (tag (cdr pair)))
          (cons*
           (dwl-key
            (key (string-append view-modifiers "-" key))
            (action `(dwl:view ,tag)))
           (dwl-key
            (key (string-append tag-modifiers "-" key))
            (action `(dwl:tag ,tag)))
           (dwl-key
            (key (string-append toggle-view-modifiers "-" key))
            (action `(dwl:toggle-view ,tag)))
           (dwl-key
            (key (string-append toggle-tag-modifiers "-" key))
            (action `(dwl:toggle-tag ,tag)))
           acc)))
      '()
      keys))))

;; Converts an operating system keyboard layout into an alist.
;; This allows us to re-use the same keyboard configuration
;; that is already being used by the system (optionally).
(define (keyboard-layout->alist layout)
  (let ((name (keyboard-layout-name layout))
        (variant (keyboard-layout-variant layout))
        (model (keyboard-layout-model layout))
        (options (keyboard-layout-options layout)))
    `(("rules" . "")
      ("layouts" . ,name)
      ("model" . ,(if (not model) "" model))
      ("variants" . ,(if (not variant) "" variant))
      ("options" . ,(if (null? options) "" (string-join options ","))))))

(define (dwl-xkb-rule->alist rule source)
  (if (keyboard-layout? rule)
      (keyboard-layout->alist rule)
      (configuration->alist
       #:type <dwl-xkb-rule>
       #:transform-value transform-xkb-rule
       #:config rule
       #:source source)))

(define (dwl-monitor-rule->alist rule source)
  (configuration->alist
   #:type <dwl-monitor-rule>
   #:transform-value transform-monitor-rule
   #:config rule
   #:source source))

(define (dwl-config->alist config)
  (let
      ((transformed-config (configuration->alist
                            #:type <dwl-config>
                            #:transform-value transform-config
                            #:config config
                            #:source config)))
    ;; Merge all keybindings into a single "keys" list.
    ;; This makes it much easier to use in C.
    ;;
    ;; The reason behind them being split into different fields in the
    ;; configuration is because it makes it easier for the user to extend without removing
    ;; all of the defaults. For example, most people will be using the standard keys
    ;; for switching tty's, and most will use some modifier and 1-9 for switching workspaces.
    (assoc-set! transformed-config "keys"
                (append (assoc-ref transformed-config "keys")
                        (assoc-ref transformed-config "tty-keys")
                        (assoc-ref transformed-config "tag-keys")))))

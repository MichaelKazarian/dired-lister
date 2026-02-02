;;; dired-lister.el --- Minor mode for previewing files in Dired -*-lexical-binding: t-*-

;; Copyright (C) 2025 Mykhailo Kazarian
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
;; Author: Michael Kazarian <michael.kazarian@gmail.com>
;; Keywords: dired, preview
;; Version: 0.1
;; Package-Requires: ((emacs "26.1"))
;; URL: https://github.com/MichaelKazarian/dired-lister

;;; Commentary:
;; This package provides a minor mode for previewing files in Dired.
;; Use `dired-lister-mode' to toggle the preview functionality.
;;
;; Installation:
;; 1. Place `dired-lister.el' in your Emacs load path.
;; 2. Add to your `.emacs' or `init.el':
;;    (require 'dired-lister)
;;    (dired-lister-mode 1) ; Enable the mode globally
;;
;; Usage:
;; - With `dired-lister-mode' enabled, open a Dired buffer.
;; - Press `TAB' (or your custom key, see `dired-lister-file-key') to preview
;;   the file at point in a side window.
;; - In the preview window, press `q' (or `dired-lister-quit-key') to close the
;;   preview, or `e' (or `dired-lister-edit-key') to edit the file.
;; - Press `q' (or `dired-lister-quit-dired-key') in Dired to quit Dired and
;;   close the preview.
;; - The preview window automatically closes when exiting Dired via `q' or
;;   `C-x k'.
;;
;; Customization:
;; - `dired-lister-auto-focus': Set to t to focus the preview window after
;;   opening (default: nil).
;; - `dired-lister-window-side': Choose the side for the preview window
;;   (`right', `left', `top', `bottom'; default: `right').
;; - `dired-lister-file-key', `dired-lister-quit-dired-key',
;;   `dired-lister-quit-key', `dired-lister-edit-key': Customize keybindings.
;; - `dired-lister-disabled-modes', `dired-lister-disabled-hooks': Customize
;;   modes and hooks to disable in the preview buffer.
;; Use `M-x customize-group RET dired-lister RET' to adjust settings.

;;; Code:

(require 'dired)

(defcustom dired-lister-auto-focus nil
  "If non-nil, automatically focus the preview window after opening it."
  :type 'boolean
  :group 'dired-lister)

(defcustom dired-lister-window-side 'right
  "Side where the preview window is displayed.
Valid values are `right', `left', `top', or `bottom'."
  :type '(choice (const right)
                 (const left)
                 (const top)
                 (const bottom))
  :group 'dired-lister)

(defcustom dired-lister-file-key (kbd "TAB")
  "Keybinding to open the file preview in Dired."
  :type 'key-sequence
  :group 'dired-lister)

(defcustom dired-lister-quit-dired-key (kbd "q")
  "Keybinding to quit Dired and close the preview."
  :type 'key-sequence
  :group 'dired-lister)

(defcustom dired-lister-quit-key (kbd "q")
  "Keybinding to close the preview window."
  :type 'key-sequence
  :group 'dired-lister)

(defcustom dired-lister-edit-key (kbd "e")
  "Keybinding to edit the previewed file."
  :type 'key-sequence
  :group 'dired-lister)

(defcustom dired-lister-disabled-modes
  '(company-mode)
  "List of major or minor modes to disable in the preview buffer."
  :type '(repeat symbol)
  :group 'dired-lister)

(defcustom dired-lister-verbose nil
  "When non-nil `dired-lister' display operation messages.
Otherwise it does not."
  :type 'boolean
  :safe #'booleanp
  :group 'dired-lister)

(defcustom dired-lister-disabled-hooks
  '(after-change-major-mode-hook)
  "List of hooks to disable in the preview buffer."
  :type '(repeat symbol)
  :group 'dired-lister)

(defvar dired-lister-buffer-name "*dired-lister*"
  "Name of the dired lister buffer.")

(define-minor-mode dired-lister-mode
  "Toggle Dired lister mode.
When enabled, provides functionality to preview files in a side window."
  :global t
  :group 'dired-lister
  :lighter " Dired-Lister"
  (if dired-lister-mode
      (progn
        (add-hook 'dired-mode-hook #'dired-lister--setup-dired-buffer)
        (add-hook 'buffer-list-update-hook #'dired-lister-cleanup)
        (dired-lister--apply-to-all-dired-buffers))
    (progn
      (remove-hook 'dired-mode-hook #'dired-lister--setup-dired-buffer)
      (remove-hook 'buffer-list-update-hook #'dired-lister-cleanup)
      (dired-lister--remove-from-all-dired-buffers)
      (dired-lister-close-previous))))

(defun dired-lister--apply-to-all-dired-buffers ()
  "Apply dired-lister settings to all existing Dired buffers."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'dired-mode)
        (dired-lister--setup-dired-buffer)))))

(defun dired-lister--remove-from-all-dired-buffers ()
  "Remove dired-lister settings from all existing Dired buffers."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'dired-mode)
        (dired-lister--revert-dired-buffer)))))

(defun dired-lister--setup-dired-buffer ()
  "Setup local bindings and hooks for Dired buffer."
  (when dired-lister-file-key
    (local-set-key dired-lister-file-key #'dired-lister-file))
  (when dired-lister-quit-dired-key
    (local-set-key dired-lister-quit-dired-key #'dired-lister-quit-dired))
  ;; nil t: make the hook buffer-local.
  (add-hook 'kill-buffer-hook #'dired-lister-close-on-dired-exit nil t))

(defun dired-lister--revert-dired-buffer ()
  "Remove local bindings and hooks from Dired buffer."
  (local-set-key dired-lister-file-key nil)
  (local-set-key dired-lister-quit-dired-key nil)
  (remove-hook 'kill-buffer-hook #'dired-lister-close-on-dired-exit t))

(defun dired-lister--buffer ()
  "Return the preview buffer if it exists."
  (get-buffer dired-lister-buffer-name))

(defun dired-lister--window ()
  "Return the window showing the preview buffer, if any."
  (get-buffer-window (dired-lister--buffer) t))

(defvar-local previewed-file nil)
(defvar-local previewed-dired-window nil)

(defun dired-lister-close-previous ()
  "Close the previous preview window if it exists."
  (let ((win (ignore-errors (dired-lister--window))))
    (when (and win (windowp win) (window-live-p win))
      (quit-window nil win))))

(defun dired-lister-prepare-buffer (file buf)
  "Prepare the preview buffer BUF with contents of FILE."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (condition-case err
          (insert-file-contents file)
        (error (message "Error inserting file contents: %s" err)))
      (let ((buffer-file-name file))
        (condition-case err
            (set-auto-mode)
          (error (message "Error in set-auto-mode: %s" err))))
      (dired-lister-disable-hooks-and-modes)
      (font-lock-mode 1)
      (font-lock-flush)
      (font-lock-ensure)
      (read-only-mode 1)
      (setq-local previewed-file file)
      (setq-local previewed-dired-window (get-mru-window nil t t)))))

(defun dired-lister-disable-hooks-and-modes ()
  "Disable dired-lister hooks and modes for current buffer.
Disable hooks and modes  specified in `dired-lister-disabled-hooks'
and `dired-lister-disabled-modes'.
Also disables the hook associated with the current major-mode."
  (when dired-lister-verbose
    (message "Running dired-lister-disable-hooks-and-modes in buffer %s"
             (current-buffer)))
  (let ((mode-hook (intern-soft (concat (symbol-name major-mode) "-hook"))))
    ;; Disable hooks from the custom list locally
    (dolist (hook dired-lister-disabled-hooks)
      (when (boundp hook)
        (make-local-variable hook)
        (set hook nil)
        (when dired-lister-verbose
          (message "Disabled hook locally: %s" hook))))
    ;; Disable the major-mode specific hook locally
    (when mode-hook
      (make-local-variable mode-hook)
      (set mode-hook nil)
      (when dired-lister-verbose
        (message "Disabled major-mode hook locally: %s for major-mode: %s" mode-hook major-mode)))
    ;; Disable modes
    (dolist (mode dired-lister-disabled-modes)
      (when (and (fboundp mode)
                 (functionp mode)
                 (boundp mode)
                 mode)
        (funcall mode -1)
        (when dired-lister-verbose
          (message "Disabled mode: %s" mode))))))

(defun dired-lister-display-buffer (buf)
  "Display the preview buffer BUF in a side window."
  (let ((buffer-list-update-hook nil)
        (window-configuration-change-hook nil)
        (display-buffer-alist nil)
        (window (display-buffer
                 buf
                 `((display-buffer-in-side-window)
                   (side . ,dired-lister-window-side)
                   (window-width . 0.5)
                   (slot . 1)
                   (window-parameters (no-delete-other-windows . t)
                                      (dedicated . t)
                                      (dired-lister-just-created . t))))))
    (when window
      (set-window-dedicated-p window t)
      (when dired-lister-auto-focus
        (select-window window)))
    window))

(defun dired-lister-setup-keybindings ()
  "Set up keybindings for the preview buffer."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map (current-local-map))
    (when dired-lister-quit-key
      (define-key map dired-lister-quit-key #'dired-lister-quit))
    (when dired-lister-edit-key
      (define-key map dired-lister-edit-key #'dired-lister-edit-file))
    (use-local-map map)))

(defun dired-lister-file ()
  "Preview the file at point in a right-side window in read-only mode."
  (interactive)
  (let* ((file (dired-get-file-for-visit))
         (buf (get-buffer-create dired-lister-buffer-name)))
    (when (file-regular-p file)
      (dired-lister-close-previous)
      (dired-lister-prepare-buffer file buf)
      ;; (with-current-buffer buf
      ;;   (dired-lister-disable-hooks-and-modes))
      (dired-lister-display-buffer buf)
      (with-selected-window (get-buffer-window buf t)
        (dired-lister-setup-keybindings)))))

(defun dired-lister-edit-file ()
  "Open the previewed file in a new editable buffer."
  (interactive)
  (when (bound-and-true-p previewed-file)
    (find-file previewed-file)))

(defun dired-lister-cleanup ()
  "Hide preview buffer and close its window if possible."
  (run-with-idle-timer
   0.3 nil
   (lambda ()
     (let ((buf (dired-lister--buffer))
           (win (dired-lister--window)))
       (when (and buf (buffer-live-p buf)
                  (not (eq (current-buffer) buf))
                  win (window-live-p win)
                  (not (window-parameter win 'dired-lister-just-created)))
         (with-selected-window win
           (quit-window nil win)))))))

(defun dired-lister-quit ()
  "Close preview and return focus to Dired window."
  (interactive)
  (let ((win (selected-window)))
    (quit-window t win)
    (when (and previewed-dired-window
               (windowp previewed-dired-window)
               (window-live-p previewed-dired-window))
      (select-window previewed-dired-window))))

(defun dired-lister-close-on-dired-exit ()
  "Close the preview window when exiting a Dired buffer."
  (when (eq major-mode 'dired-mode)
    (let ((buf (dired-lister--buffer))
          (win (dired-lister--window)))
      (when (and buf (buffer-live-p buf) win (window-live-p win))
        (when dired-lister-verbose
          (message "Closing preview window %s for buffer %s on Dired exit"
                   win buf))
        (with-selected-window win
          (quit-window nil win))))))

(defun dired-lister-quit-dired ()
  "Quit Dired and close the preview window."
  (interactive)
  (dired-lister-close-on-dired-exit)
  (quit-window))

(provide 'dired-lister)
;;; dired-lister.el ends here

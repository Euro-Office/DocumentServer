// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { describeStoredFileDeletion } from '../stored-file-delete.suite';

// PDF is worth covering separately: it is the one type the example app does
// not treat as an Office format.
describeStoredFileDeletion({
  label: 'PDF form',
  noun: 'PDF form',
  ext: 'pdf',
  rowClass: 'pdf',
});

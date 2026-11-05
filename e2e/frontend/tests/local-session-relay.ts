// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Test-only co-editing relay for local sessions with transport "host".
//
// The host page owns the "server" in that mode: every editor forwards the
// co-editing messages sdkjs would send to the DocService (onSessionMessage),
// and the host answers with sendSessionMessage. This relay plays the
// DocService part for several editors in one page, with the reply shapes of
// server/DocService/sources/DocsCoServer.js (getLock, saveChanges, isSaveLock,
// unSaveLock, unLockDocument, cursor, connectState).
//
// Editors join when they report their connection id with `sessionAuth`.
//
// Deliberately left out: waitAuth / authChanges for late joiners (all editors
// open the same bytes and join before anyone edits), Excel lock range checks
// and index recalculation (locks conflict by id only), forcesave, chat,
// save-lock expiry and reconnection.
//
// installLocalSessionRelay is injected with page.evaluate, so it must stay
// self-contained: no imports, no references to anything outside its body.

export interface RelayUser {
  id: string;
  name: string;
}

export interface RelayIdentity {
  // The id sdkjs uses for this connection (sessionAuth.connectionId, user.id
  // followed by indexUser); locks and changes carry it in their `user` field.
  userId: string;
  indexUser: number;
}

export interface LocalSessionRelay {
  addClient(clientId: string, options: { user: RelayUser; send: (message: unknown) => void }): void;
  join(clientId: string, identity: RelayIdentity): void;
  leave(clientId: string): void;
  receive(clientId: string, message: unknown): void;
  identity(clientId: string): RelayIdentity | null;
  changeCount(): number;
  log: { dir: 'in' | 'out'; client: string; type: string }[];
  errors: string[];
}

export type RelayEditorType = 'word' | 'cell' | 'slide' | 'pdf';

export function installLocalSessionRelay(editorType: RelayEditorType): void {
  type Message = Record<string, unknown> & { type?: string };
  type Lock = { time: number; user: string; block: unknown };
  type Change = {
    docid: string;
    change: unknown;
    time: number;
    user: string;
    useridoriginal: string;
  };
  type Client = {
    id: string;
    user: RelayUser;
    send: (message: unknown) => void;
    identity: RelayIdentity | null;
    pending: Message[];
  };

  const DOC_ID = 'local-session-relay';
  const clients = new Map<string, Client>();
  // Lock id -> lock. Word keys by block id, the other editors by block.guid.
  const locks: Record<string, Lock> = {};
  const changes: Change[] = [];
  let saveLockOwner: string | null = null;
  let lastParticipantsTimestamp = 0;
  const log: LocalSessionRelay['log'] = [];
  const errors: string[] = [];

  const joined = () => [...clients.values()].filter((c) => c.identity !== null);
  const others = (client: Client) => joined().filter((c) => c !== client);

  function send(client: Client, message: Message) {
    log.push({ dir: 'out', client: client.id, type: String(message.type) });
    client.send(message);
  }

  function userId(client: Client): string {
    return (client.identity as RelayIdentity).userId;
  }

  function lockId(block: unknown): string {
    if (block && typeof block === 'object' && 'guid' in block) {
      return String((block as { guid: unknown }).guid);
    }
    return String(block);
  }

  function participantsTimestamp(): number {
    // connectState is dropped by sdkjs when its timestamp goes backwards.
    lastParticipantsTimestamp = Math.max(Date.now(), lastParticipantsTimestamp + 1);
    return lastParticipantsTimestamp;
  }

  function broadcastParticipants() {
    const participants = joined().map((c) => ({
      id: userId(c),
      idOriginal: c.user.id,
      username: c.user.name,
      indexUser: (c.identity as RelayIdentity).indexUser,
      connectionId: `${DOC_ID}-${c.id}`,
      isCloseCoAuthoring: false,
      view: false,
    }));
    const message = {
      type: 'connectState',
      participantsTimestamp: participantsTimestamp(),
      participants,
      waitAuth: false,
    };
    // The DocService leaves out the joining user, which got the list in its
    // auth reply. Here auth is answered inside each editor, so everyone gets it.
    for (const c of joined()) send(c, message);
  }

  function removeUserLocks(client: Client): Lock[] {
    const removed: Lock[] = [];
    for (const id of Object.keys(locks)) {
      if (locks[id].user === userId(client)) {
        removed.push(locks[id]);
        delete locks[id];
      }
    }
    return removed;
  }

  function releaseLockMessage(removed: Lock[]): Message {
    return {
      type: 'releaseLock',
      locks: removed.map((l) => ({
        block: l.block,
        user: l.user,
        time: Date.now(),
        changes: null,
      })),
    };
  }

  function truncateChanges(deleteIndex: unknown) {
    if (typeof deleteIndex !== 'number' || deleteIndex === -1) return;
    if (deleteIndex > changes.length) {
      errors.push(`deleteIndex ${deleteIndex} is past the last change ${changes.length}`);
      return;
    }
    changes.length = deleteIndex;
  }

  function onGetLock(client: Client, message: Message) {
    const blocks = Array.isArray(message.block) ? message.block : [];
    const added: string[] = [];
    let conflict = false;
    for (const block of blocks) {
      const id = lockId(block);
      const existing = locks[id];
      if (existing && existing.user !== userId(client)) {
        conflict = true;
        continue;
      }
      locks[id] = { time: Date.now(), user: userId(client), block };
      added.push(id);
    }
    // Word keeps the blocks it could take; the other editors lock all or none.
    if (conflict && editorType !== 'word') {
      for (const id of added) delete locks[id];
    }
    const reply = { type: 'getLock', locks: { ...locks } };
    send(client, reply);
    for (const c of others(client)) send(c, reply);
  }

  function onIsSaveLock(client: Client) {
    const locked = saveLockOwner !== null && saveLockOwner !== userId(client);
    if (!locked) saveLockOwner = userId(client);
    send(client, { type: 'saveLock', saveLock: locked });
  }

  function unSaveLock(client: Client, index: number, time: number, syncChangesIndex: number) {
    if (saveLockOwner !== null && saveLockOwner !== userId(client)) {
      errors.push(`unSaveLock from ${client.id} while ${saveLockOwner} holds the save lock`);
      return;
    }
    saveLockOwner = null;
    send(client, { type: 'unSaveLock', index, time, syncChangesIndex });
  }

  function onSaveChanges(client: Client, message: Message) {
    if (saveLockOwner !== userId(client)) {
      errors.push(`saveChanges from ${client.id} without the save lock`);
      return;
    }
    if (message.startSaveChanges) truncateChanges(message.deleteIndex);
    const deleteIndex =
      message.startSaveChanges && typeof message.deleteIndex === 'number'
        ? message.deleteIndex
        : -1;
    const startIndex = changes.length;
    // Without settings.binaryChanges sdkjs sends a JSON string of change strings.
    const items: unknown[] =
      typeof message.changes === 'string'
        ? JSON.parse(message.changes)
        : Array.isArray(message.changes)
          ? message.changes
          : [];
    const time = Math.floor(Date.now() / 1000) * 1000;
    const added: Change[] = items.map((item) => ({
      docid: DOC_ID,
      change: typeof message.changes === 'string' ? JSON.stringify(item) : item,
      time,
      user: userId(client),
      useridoriginal: client.user.id,
    }));
    changes.push(...added);
    const total = changes.length;
    const changesIndex = deleteIndex === -1 && message.startSaveChanges ? startIndex : -1;

    if (!message.endSaveChanges) {
      for (const c of others(client)) {
        send(c, {
          type: 'saveChanges',
          changes: added,
          changesIndex: total,
          syncChangesIndex: total,
          endSaveChanges: false,
          locks: [],
          excelAdditionalInfo: undefined,
        });
      }
      send(client, { type: 'savePartChanges', changesIndex, syncChangesIndex: total });
      return;
    }

    const released = message.releaseLocks ? removeUserLocks(client) : [];
    for (const c of others(client)) {
      send(c, {
        type: 'saveChanges',
        changes: added,
        changesIndex: total,
        syncChangesIndex: total,
        endSaveChanges: true,
        locks: released.map((l) => ({
          block: l.block,
          user: l.user,
          time: Date.now(),
          changes: null,
        })),
        excelAdditionalInfo: message.excelAdditionalInfo,
      });
    }
    unSaveLock(client, changesIndex, time, total);
  }

  function onUnLockDocument(client: Client, message: Message) {
    truncateChanges(message.deleteIndex);
    if (message.releaseLocks) {
      const removed = removeUserLocks(client);
      if (removed.length > 0) {
        const release = releaseLockMessage(removed);
        send(client, release);
        for (const c of others(client)) send(c, release);
      }
    }
    if (message.isSave) unSaveLock(client, -1, -1, -1);
  }

  function onCursor(client: Client, message: Message) {
    const messages = [
      {
        cursor: message.cursor,
        time: Date.now(),
        user: userId(client),
        useridoriginal: client.user.id,
      },
    ];
    for (const c of others(client)) send(c, { type: 'cursor', messages });
  }

  function handle(client: Client, message: Message) {
    switch (message.type) {
      case 'getLock':
        return onGetLock(client, message);
      case 'isSaveLock':
        return onIsSaveLock(client);
      case 'saveChanges':
        return onSaveChanges(client, message);
      case 'unSaveLock':
        // An emergency release without saving; the server answers with -1s.
        return unSaveLock(client, -1, -1, -1);
      case 'unLockDocument':
        return onUnLockDocument(client, message);
      case 'cursor':
        return onCursor(client, message);
      case 'close':
        return relay.leave(client.id);
      default:
        // authChangesAck, extendSession, clientLog, getMessages, forceSaveStart...
        // need no answer for this test.
        return;
    }
  }

  const relay: LocalSessionRelay = {
    addClient(clientId, options) {
      clients.set(clientId, { id: clientId, ...options, identity: null, pending: [] });
    },
    join(clientId, identity) {
      const client = clients.get(clientId);
      if (!client) throw new Error(`unknown relay client ${clientId}`);
      client.identity = identity;
      broadcastParticipants();
      const pending = client.pending;
      client.pending = [];
      for (const message of pending) handle(client, message);
    },
    leave(clientId) {
      const client = clients.get(clientId);
      if (!client || !client.identity) return;
      const removed = removeUserLocks(client);
      if (saveLockOwner === userId(client)) saveLockOwner = null;
      client.identity = null;
      if (removed.length > 0) {
        for (const c of joined()) send(c, releaseLockMessage(removed));
      }
      broadcastParticipants();
    },
    receive(clientId, raw) {
      const client = clients.get(clientId);
      if (!client) {
        errors.push(`message from unknown client ${clientId}`);
        return;
      }
      const message = (typeof raw === 'string' ? JSON.parse(raw) : raw) as Message;
      log.push({ dir: 'in', client: clientId, type: String(message && message.type) });
      // Sent once by each editor after its local auth.
      if (message.type === 'sessionAuth') {
        relay.join(clientId, {
          userId: String(message.connectionId),
          indexUser: Number(message.indexUser),
        });
        return;
      }
      // Until the host knows the connection id, messages wait: lock and change
      // owners must match the id sdkjs compares them against.
      if (!client.identity) {
        client.pending.push(message);
        return;
      }
      try {
        handle(client, message);
      } catch (e) {
        errors.push(`${message.type}: ${e instanceof Error ? e.message : String(e)}`);
      }
    },
    identity(clientId) {
      return clients.get(clientId)?.identity ?? null;
    },
    changeCount() {
      return changes.length;
    },
    log,
    errors,
  };

  (window as unknown as { localSessionRelay: LocalSessionRelay }).localSessionRelay = relay;
}

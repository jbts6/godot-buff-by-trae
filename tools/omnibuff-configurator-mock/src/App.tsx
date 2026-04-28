import { useMemo, useRef, useState } from 'react'
import './App.css'
import { t } from './i18n/zh-CN'

type Dataset = {
  manifest: { id: string; name: string; files: Array<{ type: string; path: string }> }
  enums: { tags: string[]; event_type: string[]; action_kind: string[]; scope: string[] }
  stat_defs: Array<{
    id: string
    default: number
    min: number
    max: number
    clamp: boolean
    derived?: { type: 'LINEAR'; from: string; ratio: number } | null
    curve?: { type: 'NONE' | 'DR_SOFTCAP'; k?: number } | null
  }>
  buff_defs: Array<{
    id: string
    name: string
    tags: string[]
    duration: { type: 'PERMANENT' | 'TURNS'; turns?: number }
    stack: { mode: 'REPLACE' | 'ADD_STACK' | 'MULTI_INSTANCE'; max_stack: number }
    notes?: string
    triggers: Array<{
      event_type: string
      event_phase: string
      scope: string
      filters: Record<string, unknown>
      action: Record<string, unknown>
    }>
    effects: Array<Record<string, unknown>>
  }>
}

type NodeRef =
  | { kind: 'manifest' }
  | { kind: 'enums' }
  | { kind: 'stats_root' }
  | { kind: 'buffs_root' }
  | { kind: 'stat'; id: string }
  | { kind: 'buff'; id: string }

type Issue = {
  severity: 'error' | 'warn'
  path: string
  message: string
  node: NodeRef
}

const SAMPLE: Dataset = {
  manifest: {
    id: 'rpg_tests',
    name: 'RPG Tests Dataset',
    files: [
      { type: 'enums', path: 'res://data/rpg_tests/enums.json' },
      { type: 'stat_defs', path: 'res://data/rpg_tests/stat_defs.json' },
      { type: 'buff_defs', path: 'res://data/rpg_tests/buff_defs.json' },
    ],
  },
  enums: {
    tags: ['BUFF', 'DEBUFF', 'BONUS_DAMAGE', 'SKILL', 'DOT', 'AURA'],
    event_type: ['DAMAGE', 'DOT', 'LIFE', 'COMMAND'],
    action_kind: ['APPLY_BUFF', 'DISPEL', 'BONUS_DAMAGE', 'ADD_STACKS', 'SET_STACKS', 'HEAL'],
    scope: ['SELF', 'SOURCE', 'TARGET'],
  },
  stat_defs: [
    { id: 'HP', default: 100, min: 0, max: 99999, clamp: true, derived: { type: 'LINEAR', from: 'STR', ratio: 20 } },
    { id: 'STR', default: 0, min: 0, max: 999, clamp: true },
    { id: 'ATK', default: 10, min: 0, max: 9999, clamp: true },
    { id: 'DMG_REDUCE_RATING', default: 0, min: 0, max: 0.95, clamp: true, curve: { type: 'DR_SOFTCAP', k: 100 } },
  ],
  buff_defs: [
    {
      id: 'buff_food_atk_20_5t',
      name: '战斗口粮',
      tags: ['BUFF'],
      duration: { type: 'TURNS', turns: 5 },
      stack: { mode: 'REPLACE', max_stack: 1 },
      notes: '示例：加攻击 +20，持续 5 回合。用于演示“策划编辑—校验—导出”流程。',
      effects: [{ kind: 'modifier', stat: 'ATK', op: 'ADD', phase: 'FLAT', priority: 100, value: 20 }],
      triggers: [],
    },
    {
      id: 'buff_thorns_5',
      name: '荆棘',
      tags: ['BUFF'],
      duration: { type: 'PERMANENT' },
      stack: { mode: 'REPLACE', max_stack: 1 },
      effects: [],
      triggers: [
        {
          event_type: 'DAMAGE',
          event_phase: 'AFTER_TAKE',
          scope: 'SOURCE',
          filters: { require_hit: true },
          action: { kind: 'BONUS_DAMAGE', ratio: 0.5, require_not_bonus_damage: true },
        },
      ],
    },
  ],
}

function downloadText(filename: string, text: string) {
  const blob = new Blob([text], { type: 'application/json;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

function computeIssues(ds: Dataset): Issue[] {
  const issues: Issue[] = []
  const statIds = new Set(ds.stat_defs.map((s) => s.id))
  const buffIds = new Set<string>()

  for (const b of ds.buff_defs) {
    if (buffIds.has(b.id)) {
      issues.push({
        severity: 'error',
        path: `$.buffs["${b.id}"].id`,
        message: `重复的 buff id: ${b.id}`,
        node: { kind: 'buff', id: b.id },
      })
    }
    buffIds.add(b.id)
    if (!b.tags.length) {
      issues.push({
        severity: 'warn',
        path: `$.buffs["${b.id}"].tags`,
        message: '建议至少设置一个 tag（例如 BUFF/DEBUFF）',
        node: { kind: 'buff', id: b.id },
      })
    }
    for (const t of b.triggers) {
      if (t.action?.['kind'] === 'BONUS_DAMAGE' && t.filters?.['require_not_bonus_damage'] !== true && t.action?.['require_not_bonus_damage'] !== true) {
        issues.push({
          severity: 'warn',
          path: `$.buffs["${b.id}"].triggers[].filters.require_not_bonus_damage`,
          message: 'BONUS_DAMAGE 建议加不递归 guard：require_not_bonus_damage=true',
          node: { kind: 'buff', id: b.id },
        })
      }
    }
  }

  for (const s of ds.stat_defs) {
    if (s.derived && s.derived.type === 'LINEAR') {
      if (!statIds.has(s.derived.from)) {
        issues.push({
          severity: 'error',
          path: `$.stats["${s.id}"].derived.from`,
          message: `derived.from 引用不存在的 stat: ${s.derived.from}`,
          node: { kind: 'stat', id: s.id },
        })
      }
    }
    if (s.curve && s.curve.type === 'DR_SOFTCAP') {
      const k = Number(s.curve.k ?? 0)
      if (!(k > 0)) {
        issues.push({
          severity: 'error',
          path: `$.stats["${s.id}"].curve.k`,
          message: 'DR_SOFTCAP 需要 k > 0',
          node: { kind: 'stat', id: s.id },
        })
      }
    }
  }

  return issues
}

function nodeLabel(n: NodeRef) {
  switch (n.kind) {
    case 'manifest':
      return t('nav.manifest', 'Manifest')
    case 'enums':
      return t('nav.enums', 'Enums')
    case 'stats_root':
      return t('nav.stats', 'Stats')
    case 'buffs_root':
      return t('nav.buffs', 'Buffs')
    case 'stat':
      return n.id
    case 'buff':
      return n.id
  }
}

function nodeLabelWithName(ds: Dataset, n: NodeRef, advanced: boolean) {
  if (n.kind === 'buff') {
    const b = ds.buff_defs.find((x) => x.id === n.id)
    const name = b?.name?.trim() ? b.name.trim() : n.id
    return advanced ? `${name} (${n.id})` : name
  }
  if (n.kind === 'stat') {
    const zh = t(`stat.${n.id}`, n.id)
    return advanced ? `${zh} (${n.id})` : zh
  }
  return nodeLabel(n)
}

function crumbs(n: NodeRef) {
  switch (n.kind) {
    case 'manifest':
      return 'Dataset / manifest.json'
    case 'enums':
      return 'Dataset / enums.json'
    case 'stats_root':
      return 'Dataset / stat_defs.json'
    case 'buffs_root':
      return 'Dataset / buff_defs.json'
    case 'stat':
      return `Dataset / stat_defs.json / ${n.id}`
    case 'buff':
      return `Dataset / buff_defs.json / ${n.id}`
  }
}

type FieldType = 'string' | 'number' | 'boolean' | 'enum' | 'stat_ref' | 'buff_ref' | 'tags'

type FieldSchema = {
  key: string
  label: string
  type: FieldType
  hint?: string
  placeholder?: string
  options?: (ds: Dataset) => string[]
  i18nPrefix?: string
  showIf?: (ctx: { obj: Record<string, unknown>; ds: Dataset }) => boolean
}

type TemplateSchema = {
  label: string
  defaults: Record<string, unknown>
  fields: FieldSchema[]
}

const EFFECT_TEMPLATES: Record<string, TemplateSchema> = {
  modifier: {
    label: 'Modifier（属性修饰）',
    defaults: { kind: 'modifier', stat: 'ATK', op: 'ADD', phase: 'FLAT', priority: 100, value: 10 },
    fields: [
      { key: 'stat', label: '属性', type: 'stat_ref', hint: 'stat_id' },
      { key: 'op', label: '运算符', type: 'enum', options: () => ['ADD', 'MUL', 'OVERRIDE'], i18nPrefix: 'op' },
      { key: 'phase', label: '阶段', type: 'enum', options: () => ['FLAT', 'PERCENT', 'FINAL'], i18nPrefix: 'phase' },
      { key: 'value', label: '数值', type: 'number' },
      { key: 'priority', label: '优先级', type: 'number' },
      {
        key: 'layer',
        label: '层级（仅 PERCENT）',
        type: 'number',
        showIf: ({ obj }) => String(obj.phase ?? 'FLAT') === 'PERCENT',
      },
    ],
  },
  shield: {
    label: 'Shield（加护盾）',
    defaults: { kind: 'shield', value: 20 },
    fields: [{ key: 'value', label: '护盾值', type: 'number' }],
  },
  dot: {
    label: 'DOT（周期伤害）',
    defaults: { kind: 'dot', damage: 5, interval: 1, turns: 5, stack_mode: 'ADD' },
    fields: [
      { key: 'damage', label: '每跳伤害', type: 'number' },
      { key: 'interval', label: '间隔（秒）', type: 'number' },
      { key: 'turns', label: '持续（回合）', type: 'number' },
      { key: 'stack_mode', label: '叠加模式', type: 'enum', options: () => ['ADD', 'SET', 'MULTI_INSTANCE'] },
    ],
  },
}

const FILTER_SCHEMAS: Record<string, FieldSchema[]> = {
  DAMAGE: [
    { key: 'require_hit', label: '必须命中', type: 'boolean', hint: 'require_hit' },
    { key: 'require_crit', label: '必须暴击', type: 'boolean', hint: 'require_crit' },
    {
      key: 'require_not_bonus_damage',
      label: '不递归追加伤害',
      type: 'boolean',
      hint: 'require_not_bonus_damage',
    },
    { key: 'min_final_damage', label: '最小最终伤害', type: 'number', hint: 'min_final_damage' },
    { key: 'tag_any', label: '命中任意 Tag', type: 'tags', hint: 'tag_any' },
  ],
  LIFE: [
    { key: 'actor_id', label: '事件主体 actor_id', type: 'number', hint: 'actor_id' },
    { key: 'source_id', label: '来源 source_id', type: 'number', hint: 'source_id' },
    { key: 'tag_any', label: '命中任意 Tag', type: 'tags', hint: 'tag_any' },
  ],
  DOT: [{ key: 'tag_any', label: '命中任意 Tag', type: 'tags', hint: 'tag_any' }],
  COMMAND: [{ key: 'tag_any', label: '命中任意 Tag', type: 'tags', hint: 'tag_any' }],
}

const EVENT_PHASE_BY_TYPE: Record<string, string[]> = {
  DAMAGE: ['BUILD', 'BEFORE_DEAL', 'BEFORE_TAKE', 'RESOLVE', 'APPLY', 'AFTER_DEAL', 'AFTER_TAKE'],
  DOT: ['TURN_START', 'TURN_END'],
  LIFE: ['DEATH', 'REVIVE'],
  COMMAND: ['BEFORE', 'AFTER'],
}

const ACTION_TEMPLATES: Record<string, TemplateSchema> = {
  HEAL: {
    label: '治疗（HEAL）',
    defaults: { kind: 'HEAL', value: 5 },
    fields: [{ key: 'value', label: '治疗量', type: 'number', hint: 'value' }],
  },
  BONUS_DAMAGE: {
    label: '追加伤害（BONUS_DAMAGE）',
    defaults: { kind: 'BONUS_DAMAGE', ratio: 0.5, tags: ['BONUS_DAMAGE'] },
    fields: [
      { key: 'ratio', label: '倍率（ratio）', type: 'number', hint: 'ratio' },
      { key: 'tags', label: 'Tags（识别 bonus hit）', type: 'tags', hint: 'tags' },
    ],
  },
  APPLY_BUFF: {
    label: '施加 Buff（APPLY_BUFF）',
    defaults: { kind: 'APPLY_BUFF', buff_id: 'buff_food_atk_20_5t', stacks: 1 },
    fields: [
      { key: 'buff_id', label: '目标 Buff', type: 'buff_ref', hint: 'buff_id' },
      { key: 'stacks', label: '层数', type: 'number', hint: 'stacks' },
    ],
  },
  DISPEL: {
    label: '驱散（DISPEL）',
    defaults: { kind: 'DISPEL', mode: 'BY_TAG', tag: 'DEBUFF' },
    fields: [
      { key: 'mode', label: '模式', type: 'enum', options: () => ['BY_TAG', 'BY_ID', 'ALL'], hint: 'mode' },
      {
        key: 'tag',
        label: 'Tag（BY_TAG）',
        type: 'enum',
        options: (ds) => ds.enums.tags,
        i18nPrefix: 'tag',
        hint: 'tag',
        showIf: ({ obj }) => String(obj.mode) === 'BY_TAG',
      },
      {
        key: 'buff_id',
        label: 'Buff（BY_ID）',
        type: 'buff_ref',
        hint: 'buff_id',
        showIf: ({ obj }) => String(obj.mode) === 'BY_ID',
      },
    ],
  },
  ADD_STACKS: {
    label: '增加层数（ADD_STACKS）',
    defaults: { kind: 'ADD_STACKS', buff_id: 'buff_food_atk_20_5t', delta: 1, min_stack: 0, max_stack: 99 },
    fields: [
      { key: 'buff_id', label: '目标 Buff', type: 'buff_ref', hint: 'buff_id' },
      { key: 'delta', label: '变化量（delta）', type: 'number', hint: 'delta' },
      { key: 'min_stack', label: '最小层数', type: 'number', hint: 'min_stack' },
      { key: 'max_stack', label: '最大层数', type: 'number', hint: 'max_stack' },
    ],
  },
  SET_STACKS: {
    label: '设定层数（SET_STACKS）',
    defaults: { kind: 'SET_STACKS', buff_id: 'buff_food_atk_20_5t', value: 0, min_stack: 0, max_stack: 99 },
    fields: [
      { key: 'buff_id', label: '目标 Buff', type: 'buff_ref', hint: 'buff_id' },
      { key: 'value', label: '目标层数（value）', type: 'number', hint: 'value' },
      { key: 'min_stack', label: '最小层数', type: 'number', hint: 'min_stack' },
      { key: 'max_stack', label: '最大层数', type: 'number', hint: 'max_stack' },
    ],
  },
}

function getTemplate(name: string, templates: Record<string, TemplateSchema>, fallback: string): TemplateSchema {
  return templates[name] ?? templates[fallback]
}

function fmtEnum(i18nPrefix: string | undefined, id: string, advanced: boolean) {
  if (!i18nPrefix) return id
  const zh = t(`${i18nPrefix}.${id}`, id)
  return advanced ? `${zh} (${id})` : zh
}

function fmtStat(id: string, advanced: boolean) {
  const zh = t(`stat.${id}`, id)
  return advanced ? `${zh} (${id})` : zh
}

function fmtTag(id: string, advanced: boolean) {
  const zh = t(`tag.${id}`, id)
  return advanced ? `${zh} (${id})` : zh
}

function renderSchema(
  ds: Dataset,
  schema: FieldSchema[],
  obj: Record<string, unknown>,
  onPatch: (patch: Record<string, unknown>) => void,
  advanced: boolean,
) {
  const fields = schema.filter((f) => (f.showIf ? f.showIf({ obj, ds }) : true))

  return (
    <div className="grid2">
      {fields.map((f) => {
        const v = obj[f.key]
        const label = (
          <div className="labelRow">
            <label>{f.label}</label>
            <span className="hint">{advanced ? f.hint ?? f.key : ''}</span>
          </div>
        )

        if (f.type === 'boolean') {
          return (
            <div className="field" key={f.key}>
              {label}
              <span className="pill">
                <input
                  type="checkbox"
                  checked={Boolean(v ?? false)}
                  onChange={(e) => onPatch({ [f.key]: e.target.checked })}
                />
                {f.label}
              </span>
            </div>
          )
        }

        if (f.type === 'number') {
          return (
            <div className="field" key={f.key}>
              {label}
              <input
                className="input"
                type="number"
                value={Number(v ?? 0)}
                onChange={(e) => onPatch({ [f.key]: Number(e.target.value) })}
                placeholder={f.placeholder}
              />
            </div>
          )
        }

        if (f.type === 'enum') {
          const opts = f.options ? f.options(ds) : []
          return (
            <div className="field" key={f.key}>
              {label}
              <select
                className="select"
                value={String(v ?? opts[0] ?? '')}
                onChange={(e) => onPatch({ [f.key]: e.target.value })}
              >
                {opts.map((o) => (
                  <option key={o} value={o}>
                    {fmtEnum(f.i18nPrefix, o, advanced)}
                  </option>
                ))}
              </select>
            </div>
          )
        }

        if (f.type === 'stat_ref') {
          return (
            <div className="field" key={f.key}>
              {label}
              <select
                className="select"
                value={String(v ?? ds.stat_defs[0]?.id ?? '')}
                onChange={(e) => onPatch({ [f.key]: e.target.value })}
              >
                {ds.stat_defs.map((s) => (
                  <option key={s.id} value={s.id}>
                    {fmtStat(s.id, advanced)}
                  </option>
                ))}
              </select>
            </div>
          )
        }

        if (f.type === 'buff_ref') {
          return (
            <div className="field" key={f.key}>
              {label}
              <select
                className="select"
                value={String(v ?? ds.buff_defs[0]?.id ?? '')}
                onChange={(e) => onPatch({ [f.key]: e.target.value })}
              >
                {ds.buff_defs.map((b) => (
                  <option key={b.id} value={b.id}>
                    {advanced ? `${b.name} (${b.id})` : b.name}
                  </option>
                ))}
              </select>
            </div>
          )
        }

        if (f.type === 'tags') {
          const selected = new Set<string>(Array.isArray(v) ? (v as string[]) : [])
          return (
            <div className="field" key={f.key}>
              {label}
              <div className="inline">
                {ds.enums.tags.map((tagId) => {
                  const checked = selected.has(tagId)
                  return (
                    <span className="pill" key={tagId}>
                      <input
                        type="checkbox"
                        checked={checked}
                        onChange={(e) => {
                          const next = new Set(selected)
                          if (e.target.checked) next.add(tagId)
                          else next.delete(tagId)
                          onPatch({ [f.key]: Array.from(next) })
                        }}
                      />
                      {fmtTag(tagId, advanced)}
                    </span>
                  )
                })}
              </div>
            </div>
          )
        }

        return (
          <div className="field" key={f.key}>
            {label}
            <input
              className="input"
              value={String(v ?? '')}
              onChange={(e) => onPatch({ [f.key]: e.target.value })}
              placeholder={f.placeholder}
            />
          </div>
        )
      })}
    </div>
  )
}

function App() {
  const [ds, setDs] = useState<Dataset>(SAMPLE)
  const [selected, setSelected] = useState<NodeRef>({ kind: 'buff', id: SAMPLE.buff_defs[0].id })
  const [search, setSearch] = useState('')
  const fileRef = useRef<HTMLInputElement | null>(null)
  const [newEffectKind, setNewEffectKind] = useState<string>('modifier')
  const [newTriggerActionKind, setNewTriggerActionKind] = useState<string>('HEAL')
  const [advanced, setAdvanced] = useState<boolean>(false)

  const issues = useMemo(() => computeIssues(ds), [ds])
  const ok = issues.every((i) => i.severity !== 'error')

  const filteredStats = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return ds.stat_defs
    return ds.stat_defs.filter((s) => s.id.toLowerCase().includes(q))
  }, [ds.stat_defs, search])

  const filteredBuffs = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return ds.buff_defs
    return ds.buff_defs.filter((b) => b.id.toLowerCase().includes(q) || b.name.toLowerCase().includes(q))
  }, [ds.buff_defs, search])

  const selectedBuff = selected.kind === 'buff' ? ds.buff_defs.find((b) => b.id === selected.id) : null
  const selectedStat = selected.kind === 'stat' ? ds.stat_defs.find((s) => s.id === selected.id) : null

  function updateBuff(patch: Partial<Dataset['buff_defs'][number]>) {
    if (!selectedBuff) return
    setDs((prev) => ({
      ...prev,
      buff_defs: prev.buff_defs.map((b) => (b.id === selectedBuff.id ? { ...b, ...patch } : b)),
    }))
  }

  function updateStat(patch: Partial<Dataset['stat_defs'][number]>) {
    if (!selectedStat) return
    setDs((prev) => ({
      ...prev,
      stat_defs: prev.stat_defs.map((s) => (s.id === selectedStat.id ? { ...s, ...patch } : s)),
    }))
  }

  function onImportClick() {
    fileRef.current?.click()
  }

  async function onFilePicked(file: File) {
    const text = await file.text()
    const parsed = JSON.parse(text) as Dataset
    setDs(parsed)
    setSelected({ kind: 'manifest' })
  }

  function onExportClick() {
    downloadText(`${ds.manifest.id}.dataset.json`, JSON.stringify(ds, null, 2))
  }

  function removeBuffEffect(index: number) {
    if (!selectedBuff) return
    updateBuff({ effects: selectedBuff.effects.filter((_, i) => i !== index) })
  }

  function addBuffEffect(kind: string) {
    if (!selectedBuff) return
    const tpl = getTemplate(kind, EFFECT_TEMPLATES, 'modifier')
    const next = [...selectedBuff.effects, { ...tpl.defaults }]
    updateBuff({ effects: next })
  }

  function patchBuffEffect(index: number, patch: Record<string, unknown>) {
    if (!selectedBuff) return
    updateBuff({
      effects: selectedBuff.effects.map((e, i) => (i === index ? { ...(e as any), ...patch } : e)),
    })
  }

  function setBuffEffectKind(index: number, kind: string) {
    if (!selectedBuff) return
    const tpl = getTemplate(kind, EFFECT_TEMPLATES, 'modifier')
    updateBuff({
      effects: selectedBuff.effects.map((e, i) => (i === index ? { ...tpl.defaults } : e)),
    })
  }

  function removeBuffTrigger(index: number) {
    if (!selectedBuff) return
    updateBuff({ triggers: selectedBuff.triggers.filter((_, i) => i !== index) })
  }

  function addBuffTrigger(actionKind: string) {
    if (!selectedBuff) return
    const tpl = getTemplate(actionKind, ACTION_TEMPLATES, 'HEAL')
    const next = [
      ...selectedBuff.triggers,
      {
        event_type: 'DAMAGE',
        event_phase: 'AFTER_TAKE',
        scope: 'SELF',
        filters: { require_hit: true },
        action: { ...tpl.defaults },
      },
    ]
    updateBuff({ triggers: next })
  }

  function patchBuffTrigger(index: number, patch: Partial<Dataset['buff_defs'][number]['triggers'][number]>) {
    if (!selectedBuff) return
    updateBuff({
      triggers: selectedBuff.triggers.map((t, i) => (i === index ? { ...t, ...patch } : t)),
    })
  }

  function patchBuffTriggerFilters(index: number, patch: Record<string, unknown>) {
    if (!selectedBuff) return
    updateBuff({
      triggers: selectedBuff.triggers.map((t, i) =>
        i === index ? { ...t, filters: { ...(t.filters ?? {}), ...patch } } : t,
      ),
    })
  }

  function patchBuffTriggerAction(index: number, patch: Record<string, unknown>) {
    if (!selectedBuff) return
    updateBuff({
      triggers: selectedBuff.triggers.map((t, i) =>
        i === index ? { ...t, action: { ...(t.action ?? {}), ...patch } } : t,
      ),
    })
  }

  function setTriggerActionKind(index: number, kind: string) {
    if (!selectedBuff) return
    const tpl = getTemplate(kind, ACTION_TEMPLATES, 'HEAL')
    updateBuff({
      triggers: selectedBuff.triggers.map((t, i) => (i === index ? { ...t, action: { ...tpl.defaults } } : t)),
    })
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <h1>OmniBuff 配置器（Mock）</h1>
          <span className="chip" title="此处为纯前端 mock，后续可替换为 Tauri 文件对话框 + Rust/Python 校验后端。">
            <span className="chipDot" style={{ background: ok ? 'var(--ok)' : 'var(--danger)' }} />
            {ok ? '已通过校验（Mock）' : '存在错误（Mock）'}
          </span>
          <span className="chip">
            Dataset: <span style={{ fontFamily: 'var(--mono)' }}>{ds.manifest.id}</span>
          </span>
        </div>

        <div className="actions">
          <input
            ref={fileRef}
            type="file"
            accept="application/json,.json"
            style={{ display: 'none' }}
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) void onFilePicked(f)
              e.currentTarget.value = ''
            }}
          />
          <button className="btn" onClick={onImportClick} type="button">
            导入
          </button>
          <button className="btn btnPrimary" onClick={onExportClick} type="button">
            导出
          </button>
          <button
            className="btn"
            type="button"
            onClick={() => setAdvanced((v) => !v)}
            title="高级模式：显示英文 key/ID，适合程序与调试使用。"
          >
            {advanced ? '高级：开' : '高级：关'}
          </button>
        </div>
      </header>

      <div className="layout">
        <aside className="sidebar">
          <div className="panelHeader">
            <h2>导航树</h2>
          </div>
          <div style={{ padding: 12 }}>
            <input
              className="search"
              value={search}
              placeholder="搜索 stat / buff…"
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <div className="scroll">
            <div className="tree">
              {[
                { node: { kind: 'manifest' } as NodeRef, meta: '1' },
                { node: { kind: 'enums' } as NodeRef, meta: String(ds.enums.tags.length) },
                { node: { kind: 'stats_root' } as NodeRef, meta: String(ds.stat_defs.length) },
                ...filteredStats.map((s) => ({ node: { kind: 'stat', id: s.id } as NodeRef, meta: 'stat' })),
                { node: { kind: 'buffs_root' } as NodeRef, meta: String(ds.buff_defs.length) },
                ...filteredBuffs.map((b) => ({ node: { kind: 'buff', id: b.id } as NodeRef, meta: `${b.triggers.length}T` })),
              ].map(({ node, meta }) => {
                const active = JSON.stringify(node) === JSON.stringify(selected)
                const dot =
                  node.kind === 'buff' ? 'treeDot treeDotBuff' : node.kind === 'stat' ? 'treeDot treeDotStat' : 'treeDot'
                return (
                  <div
                    key={`${node.kind}:${'id' in node ? node.id : ''}:${meta}`}
                    className={`treeItem ${active ? 'treeItemActive' : ''}`}
                    onClick={() => setSelected(node)}
                    role="button"
                    tabIndex={0}
                  >
                    <span className={dot} />
                    <span>{nodeLabelWithName(ds, node, advanced)}</span>
                    <span className="treeMeta">{meta}</span>
                  </div>
                )
              })}
            </div>
          </div>
        </aside>

        <main className="main">
          <div className="mainInner">
            <div className="sheet">
              <div className="sheetTop">
                <div className="sheetTitle">
                  <h3>{nodeLabelWithName(ds, selected, advanced)}</h3>
                  <div className="crumbs">{crumbs(selected)}</div>
                </div>
                <span className="chip">
                  选中类型：<span style={{ fontFamily: 'var(--mono)' }}>{selected.kind}</span>
                </span>
              </div>

              <div className="sheetBody">
                {selected.kind === 'manifest' && (
                  <>
                    <div className="field">
                      <div className="labelRow">
                        <label>Dataset 名称</label>
                        <span className="hint">manifest.name</span>
                      </div>
                      <input
                        className="input"
                        value={ds.manifest.name}
                        onChange={(e) => setDs((p) => ({ ...p, manifest: { ...p.manifest, name: e.target.value } }))}
                      />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>Dataset ID</label>
                        <span className="hint">manifest.id</span>
                      </div>
                      <input
                        className="input"
                        value={ds.manifest.id}
                        onChange={(e) => setDs((p) => ({ ...p, manifest: { ...p.manifest, id: e.target.value } }))}
                      />
                    </div>
                    <div className="field row2">
                      <div className="labelRow">
                        <label>Files</label>
                        <span className="hint">manifest.files</span>
                      </div>
                      <textarea className="textarea" value={JSON.stringify(ds.manifest.files, null, 2)} readOnly />
                    </div>
                  </>
                )}

                {selected.kind === 'enums' && (
                  <>
                    <div className="field row2">
                      <div className="labelRow">
                        <label>Tags</label>
                        <span className="hint">enums.tags</span>
                      </div>
                      <textarea
                        className="textarea"
                        value={ds.enums.tags.join('\n')}
                        onChange={(e) =>
                          setDs((p) => ({ ...p, enums: { ...p.enums, tags: e.target.value.split('\n').filter(Boolean) } }))
                        }
                      />
                    </div>
                  </>
                )}

                {selected.kind === 'stat' && selectedStat && (
                  <>
                    <div className="field">
                      <div className="labelRow">
                        <label>Stat ID</label>
                        <span className="hint">id</span>
                      </div>
                      <input className="input" value={selectedStat.id} readOnly />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>默认值</label>
                        <span className="hint">default</span>
                      </div>
                      <input
                        className="input"
                        type="number"
                        value={selectedStat.default}
                        onChange={(e) => updateStat({ default: Number(e.target.value) })}
                      />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>min</label>
                        <span className="hint">min</span>
                      </div>
                      <input className="input" type="number" value={selectedStat.min} onChange={(e) => updateStat({ min: Number(e.target.value) })} />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>max</label>
                        <span className="hint">max</span>
                      </div>
                      <input className="input" type="number" value={selectedStat.max} onChange={(e) => updateStat({ max: Number(e.target.value) })} />
                    </div>
                    <div className="field row2">
                      <div className="labelRow">
                        <label>derived（LINEAR）</label>
                        <span className="hint">derived</span>
                      </div>
                      <textarea
                        className="textarea"
                        value={JSON.stringify(selectedStat.derived ?? null, null, 2)}
                        onChange={(e) => {
                          try {
                            const v = JSON.parse(e.target.value)
                            updateStat({ derived: v })
                          } catch {
                            // mock：不阻断输入
                          }
                        }}
                      />
                    </div>
                  </>
                )}

                {selected.kind === 'buff' && selectedBuff && (
                  <>
                    <div className="field">
                      <div className="labelRow">
                        <label>Buff ID</label>
                        <span className="hint">id</span>
                      </div>
                      <input className="input" value={selectedBuff.id} readOnly />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>名称</label>
                        <span className="hint">name</span>
                      </div>
                      <input className="input" value={selectedBuff.name} onChange={(e) => updateBuff({ name: e.target.value })} />
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>Tags</label>
                        <span className="hint">tags</span>
                      </div>
                      <div className="inline">
                        {ds.enums.tags.map((tagId) => {
                          const checked = selectedBuff.tags.includes(tagId)
                          return (
                            <span className="pill" key={tagId}>
                              <input
                                type="checkbox"
                                checked={checked}
                                onChange={(e) => {
                                  const next = new Set(selectedBuff.tags)
                                  if (e.target.checked) next.add(tagId)
                                  else next.delete(tagId)
                                  updateBuff({ tags: Array.from(next) })
                                }}
                              />
                              {fmtTag(tagId, advanced)}
                            </span>
                          )
                        })}
                      </div>
                    </div>
                    <div className="field">
                      <div className="labelRow">
                        <label>持续</label>
                        <span className="hint">duration</span>
                      </div>
                      <div className="grid2">
                        <div className="inline">
                          <select
                            className="select"
                            value={selectedBuff.duration.type}
                            onChange={(e) => {
                              const t = e.target.value as Dataset['buff_defs'][number]['duration']['type']
                              if (t === 'PERMANENT') updateBuff({ duration: { type: 'PERMANENT' } })
                              else updateBuff({ duration: { type: 'TURNS', turns: selectedBuff.duration.turns ?? 3 } })
                            }}
                          >
                            <option value="PERMANENT">
                              {advanced ? `${t('duration.PERMANENT', 'PERMANENT')} (PERMANENT)` : t('duration.PERMANENT', 'PERMANENT')}
                            </option>
                            <option value="TURNS">
                              {advanced ? `${t('duration.TURNS', 'TURNS')} (TURNS)` : t('duration.TURNS', 'TURNS')}
                            </option>
                          </select>
                          {selectedBuff.duration.type === 'TURNS' && (
                            <input
                              className="input"
                              type="number"
                              min={1}
                              value={selectedBuff.duration.turns ?? 1}
                              onChange={(e) =>
                                updateBuff({ duration: { type: 'TURNS', turns: Math.max(1, Number(e.target.value)) } })
                              }
                              style={{ width: 120 }}
                            />
                          )}
                        </div>
                        <div className="miniNote">
                          这是 mock：后续会做成更完整的模板（PERMANENT / TURNS / UNTIL_DISPEL 等）。
                        </div>
                      </div>
                    </div>
                    <div className="field row2">
                      <div className="labelRow">
                        <label>Effects</label>
                        <span className="hint">effects</span>
                      </div>
                      <div className="list">
                        {selectedBuff.effects.map((eff, idx) => {
                          const effObj = (eff ?? {}) as Record<string, unknown>
                          const kind = String(effObj.kind ?? 'modifier')
                          const tpl = getTemplate(kind, EFFECT_TEMPLATES, 'modifier')
                          return (
                            <div className="listRow" key={`eff:${idx}`}>
                              <div className="rowHead">
                                <div className="rowTitle">
                                  Effect #{idx + 1} · {tpl.label}
                                </div>
                                <div className="inline">
                                  <select
                                    className="select"
                                    value={kind}
                                    onChange={(e) => setBuffEffectKind(idx, e.target.value)}
                                    title="effect kind"
                                  >
                                    {Object.entries(EFFECT_TEMPLATES).map(([k, t]) => (
                                      <option key={k} value={k}>
                                        {t.label}
                                      </option>
                                    ))}
                                  </select>
                                <button className="iconBtn" type="button" onClick={() => removeBuffEffect(idx)}>
                                  删除
                                </button>
                                </div>
                              </div>
                              {renderSchema(ds, tpl.fields, effObj, (patch) => patchBuffEffect(idx, patch), advanced)}
                            </div>
                          )
                        })}
                        <div className="inline">
                          <select className="select" value={newEffectKind} onChange={(e) => setNewEffectKind(e.target.value)}>
                            {Object.entries(EFFECT_TEMPLATES).map(([k, tpl]) => (
                              <option key={k} value={k}>
                                {tpl.label}
                              </option>
                            ))}
                          </select>
                          <button className="addRowBtn" type="button" onClick={() => addBuffEffect(newEffectKind)}>
                            + 添加 Effect
                          </button>
                        </div>
                      </div>
                    </div>
                    <div className="field row2">
                      <div className="labelRow">
                        <label>Triggers</label>
                        <span className="hint">triggers</span>
                      </div>
                      <div className="list">
                        {selectedBuff.triggers.map((tr, idx) => {
                          const actionKind = String((tr.action as any)?.kind ?? 'HEAL')
                          const actionTpl = getTemplate(actionKind, ACTION_TEMPLATES, 'HEAL')
                          const filterSchema = FILTER_SCHEMAS[String(tr.event_type)] ?? []
                          return (
                            <div className="listRow" key={`tr:${idx}`}>
                              <div className="rowHead">
                                <div className="rowTitle">Trigger #{idx + 1}</div>
                                <button className="iconBtn" type="button" onClick={() => removeBuffTrigger(idx)}>
                                  删除
                                </button>
                              </div>
                              <div className="grid2">
                                <div className="inline">
                                  <select
                                    className="select"
                                    value={tr.event_type}
                                    onChange={(e) => {
                                      const et = e.target.value
                                      const phases = EVENT_PHASE_BY_TYPE[et] ?? []
                                      const nextPhase = phases.includes(tr.event_phase) ? tr.event_phase : (phases[0] ?? tr.event_phase)
                                      patchBuffTrigger(idx, { event_type: et, event_phase: nextPhase })
                                    }}
                                  >
                                    {ds.enums.event_type.map((x) => (
                                      <option key={x} value={x}>
                                        {advanced ? `${t(`event_type.${x}`, x)} (${x})` : t(`event_type.${x}`, x)}
                                      </option>
                                    ))}
                                  </select>
                                  <select
                                    className="select"
                                    value={tr.event_phase}
                                    onChange={(e) => patchBuffTrigger(idx, { event_phase: e.target.value })}
                                    style={{ width: 200 }}
                                  >
                                    {(EVENT_PHASE_BY_TYPE[String(tr.event_type)] ?? []).map((p) => (
                                      <option key={p} value={p}>
                                        {advanced ? `${t(`event_phase.${p}`, p)} (${p})` : t(`event_phase.${p}`, p)}
                                      </option>
                                    ))}
                                  </select>
                                  <select
                                    className="select"
                                    value={tr.scope}
                                    onChange={(e) => patchBuffTrigger(idx, { scope: e.target.value })}
                                  >
                                    {ds.enums.scope.map((x) => (
                                      <option key={x} value={x}>
                                        {advanced ? `${t(`scope.${x}`, x)} (${x})` : t(`scope.${x}`, x)}
                                      </option>
                                    ))}
                                  </select>
                                </div>
                                <div className="miniNote">
                                  Filters/Action 将按 schema 渲染（event_type 与 action.kind 决定字段集）
                                </div>
                              </div>

                              <div className="rowTitle" style={{ marginTop: 8 }}>Filters</div>
                              {renderSchema(
                                ds,
                                filterSchema,
                                (tr.filters ?? {}) as Record<string, unknown>,
                                (patch) => patchBuffTriggerFilters(idx, patch),
                                advanced,
                              )}

                              <div className="rowTitle" style={{ marginTop: 10 }}>Action</div>
                              <div className="inline" style={{ marginBottom: 10 }}>
                                <select
                                  className="select"
                                  value={actionKind}
                                  onChange={(e) => setTriggerActionKind(idx, e.target.value)}
                                >
                                  {ds.enums.action_kind.map((x) => (
                                    <option key={x} value={x}>
                                      {advanced ? `${t(`action_kind.${x}`, x)} (${x})` : t(`action_kind.${x}`, x)}
                                    </option>
                                  ))}
                                </select>
                                <span className="miniNote">{actionTpl.label}</span>
                              </div>
                              {renderSchema(
                                ds,
                                actionTpl.fields,
                                (tr.action ?? {}) as Record<string, unknown>,
                                (patch) => patchBuffTriggerAction(idx, patch),
                                advanced,
                              )}
                            </div>
                          )
                        })}
                        <div className="inline">
                          <select
                            className="select"
                            value={newTriggerActionKind}
                            onChange={(e) => setNewTriggerActionKind(e.target.value)}
                          >
                            {ds.enums.action_kind.map((x) => (
                              <option key={x} value={x}>
                                {advanced ? `${t(`action_kind.${x}`, x)} (${x})` : t(`action_kind.${x}`, x)}
                              </option>
                            ))}
                          </select>
                          <button className="addRowBtn" type="button" onClick={() => addBuffTrigger(newTriggerActionKind)}>
                            + 添加 Trigger
                          </button>
                        </div>
                      </div>
                    </div>
                  </>
                )}

                {selected.kind === 'stats_root' && (
                  <div className="field row2">
                    <div className="labelRow">
                      <label>stat_defs.json（预览）</label>
                      <span className="hint">只读预览</span>
                    </div>
                    <textarea className="textarea" value={JSON.stringify(ds.stat_defs, null, 2)} readOnly />
                  </div>
                )}

                {selected.kind === 'buffs_root' && (
                  <div className="field row2">
                    <div className="labelRow">
                      <label>buff_defs.json（预览）</label>
                      <span className="hint">只读预览</span>
                    </div>
                    <textarea className="textarea" value={JSON.stringify(ds.buff_defs, null, 2)} readOnly />
                  </div>
                )}
              </div>
            </div>
          </div>
        </main>

        <aside className="rightbar">
          <div className="panelHeader">
            <h2>校验 / Issues</h2>
            <span className="chip">
              <span className="chipDot" style={{ background: ok ? 'var(--ok)' : 'var(--warn)' }} />
              {issues.filter((i) => i.severity === 'error').length}E / {issues.filter((i) => i.severity === 'warn').length}W
            </span>
          </div>
          <div className="scroll">
            <div className="issues">
              {issues.length === 0 ? (
                <div className="issue" style={{ cursor: 'default' }}>
                  <div className="issueMsg">看起来一切正常（Mock）</div>
                  <div className="issueMeta">接下来：接入真实 validators → 输出 file/loc/path → 支持一键跳转</div>
                </div>
              ) : (
                issues.map((iss, idx) => (
                  <div
                    key={`${iss.path}:${idx}`}
                    className="issue"
                    onClick={() => setSelected(iss.node)}
                    role="button"
                    tabIndex={0}
                  >
                    <div className="issueTop">
                      <span className={`sev ${iss.severity === 'error' ? 'sevErr' : 'sevWarn'}`} />
                      <div className="issueMsg">{iss.message}</div>
                    </div>
                    <div className="issueMeta">{iss.path}</div>
                  </div>
                ))
              )}
            </div>
          </div>
        </aside>
      </div>
    </div>
  )
}

export default App

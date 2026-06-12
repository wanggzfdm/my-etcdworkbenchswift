<script setup lang="ts">

import {onMounted, onUnmounted, ref, watch} from "vue";
import {createJSONEditor, JsonEditor, Content, OnChangeStatus} from "vanilla-jsoneditor";
import {_encodeStringToBytes} from "~/common/utils.ts";

import "vanilla-jsoneditor/themes/jse-theme-dark.css";

const props = defineProps({
  value: {
    type: String,
    default: () => "",
  },
  readOnly: {
    type: Boolean,
    default: false,
  },
  darkTheme: {
    type: Boolean,
    default: false,
  },
})

const emits = defineEmits(["change"])

const containerRef = ref<HTMLDivElement>()
let editor: JsonEditor | undefined

//  当前编辑器中的文本内容（始终保持为字符串），用于读取与脏检查
const currentText = ref<string>(props.value)

//  根据传入字符串构造 JSONEditor 的 content。
//  能解析为 JSON 时使用 json 模式，否则退化为 text 模式，避免无效 JSON 直接报错。
const buildContent = (value: string): Content => {
  return {text: value}
}

//  从编辑器读取当前文本内容
const readText = (): string => {
  if (!editor) {
    return currentText.value
  }
  const content = editor.get() as { text?: string; json?: unknown }
  if (content.text !== undefined) {
    return content.text
  }
  if (content.json !== undefined) {
    return JSON.stringify(content.json, null, 2)
  }
  return currentText.value
}

const onChange = (_content: Content, _previous: Content, status: OnChangeStatus) => {
  const text = readText()
  currentText.value = text
  emits("change", {
    data: text,
    modified: text !== props.value,
    //  内容是否存在解析/校验错误
    hasError: !!(status && status.contentErrors)
  })
}

onMounted(() => {
  if (!containerRef.value) {
    return
  }
  editor = createJSONEditor({
    target: containerRef.value,
    props: {
      content: buildContent(props.value),
      mode: 'tree' as any,
      readOnly: props.readOnly,
      mainMenuBar: true,
      navigationBar: true,
      statusBar: true,
      onChange,
    }
  })
})

onUnmounted(() => {
  if (editor) {
    editor.destroy()
    editor = undefined
  }
})

watch(
    () => props.value,
    (newVal) => {
      if (editor && newVal !== currentText.value) {
        currentText.value = newVal
        editor.update(buildContent(newVal))
      }
    }
)

watch(
    () => props.readOnly,
    (newVal) => {
      if (editor) {
        editor.updateProps({readOnly: newVal})
      }
    }
)

const readDataString = (): string => {
  return readText()
}

const readDataBytes = (): number[] => {
  return _encodeStringToBytes(readText())
}

//  尝试将内容规整为合法 JSON 字符串。若内容非法则抛出异常。
const tryFormatContent = (): Promise<string | undefined> => {
  return new Promise((resolve, reject) => {
    const text = readText()
    try {
      const formatted = JSON.stringify(JSON.parse(text), null, 2)
      resolve(formatted)
    } catch (e) {
      reject(e)
    }
  })
}

defineExpose({
  readDataBytes,
  readDataString,
  tryFormatContent,
})

</script>

<template>
  <div class="json-tree-editor fill-height"
       :class="{ 'jse-theme-dark': darkTheme }"
       ref="containerRef"
  ></div>
</template>

<style scoped lang="scss">
.json-tree-editor {
  width: 100%;
  height: 100%;
  overflow: hidden;
  --jse-font-size-main-menu: 14px;
}
</style>

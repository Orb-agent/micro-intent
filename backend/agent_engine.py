"""
Lumi Agent Engine: Gemini orchestration with Google Workspace tool calling.
"""
import os
from typing import Dict, Any, List, Optional
from google import genai
from google.genai import types

from services import (
    calendar_service,
    gmail_service,
    drive_service,
    docs_service,
    tasks_service,
)

LUMI_SYSTEM_INSTRUCTION = """
Eres Lumi, una asistente ejecutiva de inteligencia artificial ultra eficiente, proactiva y cálida.
Tu propósito es ayudar al usuario a gestionar su vida profesional mediante Google Workspace (Gmail, Calendar, Drive, Docs, Tasks).

Reglas de conducta:
1. Comunícate en español, con un tono cordial, ejecutivo y orientado a la acción.
2. Usa las herramientas proporcionadas cuando el usuario pida agendar eventos, consultar información, redactar correos o crear notas y tareas.
3. Resume con claridad las acciones realizadas y los detalles clave (fechas, horas, destinatarios, títulos o enlaces generados).
4. Si falta información crucial para ejecutar una acción irreversible (como enviar un correo con datos ambiguos), especifica lo que falta.
5. Presenta tus respuestas de manera limpia con viñetas o formato estructurado.
"""


def build_workspace_tool() -> types.Tool:
    """Builds the Tool containing FunctionDeclarations for Google Workspace APIs."""
    declarations = [
        types.FunctionDeclaration(
            name="calendar_list_events",
            description="Lista los próximos eventos del calendario de Google del usuario.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "max_results": {
                        "type": "integer",
                        "description": "Máximo número de eventos a consultar (por defecto 10)"
                    },
                    "time_min": {
                        "type": "string",
                        "description": "Fecha y hora mínima de búsqueda en formato ISO 8601 (ej: 2026-10-10T12:00:00Z)"
                    }
                }
            }
        ),
        types.FunctionDeclaration(
            name="calendar_create_event",
            description="Crea un nuevo evento en Google Calendar.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "summary": {
                        "type": "string",
                        "description": "Título o asunto del evento"
                    },
                    "start_time": {
                        "type": "string",
                        "description": "Fecha y hora de inicio en formato ISO 8601 (ej: 2026-10-15T10:00:00+02:00)"
                    },
                    "end_time": {
                        "type": "string",
                        "description": "Fecha y hora de fin en formato ISO 8601 (ej: 2026-10-15T11:00:00+02:00)"
                    },
                    "description": {
                        "type": "string",
                        "description": "Descripción o notas del evento"
                    },
                    "attendees": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Lista de direcciones de correo electrónico de los invitados"
                    }
                },
                "required": ["summary", "start_time", "end_time"]
            }
        ),
        types.FunctionDeclaration(
            name="gmail_list_messages",
            description="Busca y lista correos electrónicos de Gmail según un filtro.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Filtro de búsqueda de Gmail (ej: 'is:unread', 'from:cliente@empresa.com')"
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Máximo de correos a consultar (por defecto 5)"
                    }
                }
            }
        ),
        types.FunctionDeclaration(
            name="gmail_send_email",
            description="Envía un correo electrónico a través de Gmail.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "to": {
                        "type": "string",
                        "description": "Correo electrónico del destinatario"
                    },
                    "subject": {
                        "type": "string",
                        "description": "Asunto del correo"
                    },
                    "body": {
                        "type": "string",
                        "description": "Contenido o cuerpo del correo electrónico"
                    }
                },
                "required": ["to", "subject", "body"]
            }
        ),
        types.FunctionDeclaration(
            name="tasks_list_tasks",
            description="Obtiene las tareas pendientes de Google Tasks.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "tasklist": {
                        "type": "string",
                        "description": "Identificador de la lista de tareas ('@default' por defecto)"
                    }
                }
            }
        ),
        types.FunctionDeclaration(
            name="tasks_create_task",
            description="Crea una nueva tarea pendiente en Google Tasks.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Título o descripción de la tarea"
                    },
                    "notes": {
                        "type": "string",
                        "description": "Notas o detalles adicionales"
                    },
                    "due": {
                        "type": "string",
                        "description": "Fecha límite en formato RFC 3339 (ej: 2026-10-20T18:00:00Z)"
                    }
                },
                "required": ["title"]
            }
        ),
        types.FunctionDeclaration(
            name="docs_create_document",
            description="Crea un nuevo documento de Google Docs.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Título del documento"
                    },
                    "content": {
                        "type": "string",
                        "description": "Texto inicial a insertar en el documento"
                    }
                },
                "required": ["title"]
            }
        ),
        types.FunctionDeclaration(
            name="drive_search_files",
            description="Busca archivos y documentos en Google Drive.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Query de búsqueda en Google Drive (ej: name contains 'Minuta')"
                    },
                    "page_size": {
                        "type": "integer",
                        "description": "Cantidad de archivos a devolver (por defecto 10)"
                    }
                }
            }
        )
    ]
    return types.Tool(function_declarations=declarations)


def dispatch_tool_call(tool_name: str, args: Dict[str, Any], access_token: str) -> Any:
    """Executes the specific Workspace tool using the user's bearer token."""
    if tool_name == "calendar_list_events":
        return calendar_service.list_events(
            access_token=access_token,
            max_results=args.get("max_results", 10),
            time_min=args.get("time_min")
        )
    elif tool_name == "calendar_create_event":
        return calendar_service.create_event(
            access_token=access_token,
            summary=args["summary"],
            start_time=args["start_time"],
            end_time=args["end_time"],
            description=args.get("description"),
            attendees=args.get("attendees")
        )
    elif tool_name == "gmail_list_messages":
        return gmail_service.list_messages(
            access_token=access_token,
            query=args.get("query", "is:unread"),
            max_results=args.get("max_results", 5)
        )
    elif tool_name == "gmail_send_email":
        return gmail_service.send_email(
            access_token=access_token,
            to=args["to"],
            subject=args["subject"],
            body=args["body"]
        )
    elif tool_name == "tasks_list_tasks":
        return tasks_service.list_tasks(
            access_token=access_token,
            tasklist=args.get("tasklist", "@default")
        )
    elif tool_name == "tasks_create_task":
        return tasks_service.create_task(
            access_token=access_token,
            title=args["title"],
            notes=args.get("notes"),
            due=args.get("due")
        )
    elif tool_name == "docs_create_document":
        return docs_service.create_document(
            access_token=access_token,
            title=args["title"],
            content=args.get("content")
        )
    elif tool_name == "drive_search_files":
        return drive_service.search_files(
            access_token=access_token,
            query=args.get("query"),
            page_size=args.get("page_size", 10)
        )
    else:
        raise ValueError(f"Unknown Workspace tool: {tool_name}")


class LumiAgent:
    """Orchestrates conversations and tool executions with Google Gemini."""

    def __init__(self, api_key: Optional[str] = None, model_name: str = "gemini-2.5-flash"):
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        self.client = genai.Client(api_key=self.api_key)
        self.model_name = model_name
        self.workspace_tool = build_workspace_tool()

    def run(self, prompt: str, access_token: str, max_turns: int = 5) -> Dict[str, Any]:
        """
        Executes a multi-turn reasoning loop:
        1. Sends prompt to Gemini with Workspace tools.
        2. Loops while Gemini requests function calls.
        3. Executes requested functions using access_token.
        4. Returns the synthesized text response and list of executed actions.
        """
        executed_actions: List[Dict[str, Any]] = []
        user_prompt_content = types.Content(
            role="user",
            parts=[types.Part.from_text(text=prompt)]
        )
        contents = [user_prompt_content]

        for _ in range(max_turns):
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=contents,
                config=types.GenerateContentConfig(
                    system_instruction=LUMI_SYSTEM_INSTRUCTION,
                    tools=[self.workspace_tool],
                    temperature=0.3
                )
            )

            # Check if any candidate has content
            candidate = response.candidates[0] if response.candidates else None
            if not candidate or not candidate.content:
                break

            contents.append(candidate.content)

            # Check for function calls
            function_calls = response.function_calls
            if not function_calls:
                # Model finished its turn and delivered final text
                return {
                    "reply": response.text or "",
                    "actions": executed_actions
                }

            # Execute all function calls requested by the model
            tool_response_parts = []
            for call in function_calls:
                tool_name = call.name
                tool_args = call.args or {}

                try:
                    raw_result = dispatch_tool_call(tool_name, tool_args, access_token)
                    action_record = {
                        "tool": tool_name,
                        "arguments": tool_args,
                        "status": "success",
                        "result": raw_result
                    }
                    tool_resp_payload = {"result": raw_result}
                except Exception as e:
                    action_record = {
                        "tool": tool_name,
                        "arguments": tool_args,
                        "status": "error",
                        "error": str(e)
                    }
                    tool_resp_payload = {"error": str(e)}

                executed_actions.append(action_record)
                tool_response_parts.append(
                    types.Part.from_function_response(
                        name=tool_name,
                        response=tool_resp_payload
                    )
                )

            # Add tool responses to contents for the next iteration
            contents.append(
                types.Content(
                    role="tool",
                    parts=tool_response_parts
                )
            )

        # Fallback if loop finishes
        return {
            "reply": response.text or "Acciones procesadas correctamente.",
            "actions": executed_actions
        }

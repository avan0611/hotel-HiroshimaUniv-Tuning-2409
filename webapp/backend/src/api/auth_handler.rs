use crate::domains::auth_service::AuthService;
use crate::domains::dto::auth::{LoginRequestDto, LogoutRequestDto, RegisterRequestDto};
use crate::errors::AppError;
use crate::repositories::auth_repository::AuthRepositoryImpl;
use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
pub struct ValidateSessionQueryParams {
    session_token: Option<String>,
}

#[derive(Serialize, Debug)]
pub struct ValidationResponse {
    is_valid: bool,
}

pub async fn validate_session_handler(
    service: web::Data<AuthService<AuthRepositoryImpl>>,
    query: web::Query<ValidateSessionQueryParams>,
) -> Result<HttpResponse, AppError> {
    match &query.session_token {
        Some(session_token) => match service.validate_session(session_token.as_str()).await {
            Ok(is_valid) => Ok(HttpResponse::Ok().json(ValidationResponse { is_valid })),
            Err(_) => Ok(HttpResponse::Unauthorized().json(ValidationResponse { is_valid: false })),
        },
        None => Ok(HttpResponse::BadRequest().json(ValidationResponse { is_valid: false })),
    }
}

pub async fn register_handler(
    service: web::Data<AuthService<AuthRepositoryImpl>>,
    req: web::Json<RegisterRequestDto>,
) -> Result<HttpResponse, AppError> {
    if req.username.is_empty() || req.password.is_empty() {
        return Ok(HttpResponse::BadRequest().json("Username and password cannot be empty."));
    }
    match service
        .register_user(&req.username, &req.password, &req.role, req.area_id)
        .await
    {
        Ok(response) => Ok(HttpResponse::Created().json(response)),
        Err(err) => Err(err),
    }
}

pub async fn login_handler(
    service: web::Data<AuthService<AuthRepositoryImpl>>,
    req: web::Json<LoginRequestDto>,
) -> Result<HttpResponse, AppError> {
    if req.username.is_empty() || req.password.is_empty() {
        return Ok(HttpResponse::BadRequest().json("Username and password cannot be empty."));
    }
    match service.login_user(&req.username, &req.password).await {
        Ok(response) => Ok(HttpResponse::Ok().json(response)),
        Err(err) => Err(err),
    }
}

pub async fn logout_handler(
    service: web::Data<AuthService<AuthRepositoryImpl>>,
    req: web::Json<LogoutRequestDto>,
) -> Result<HttpResponse, AppError> {
    if req.session_token.is_empty() {
        return Ok(HttpResponse::BadRequest().json("Session token cannot be empty"));
    }
    match service.logout_user(&req.session_token).await {
        Ok(_) => Ok(HttpResponse::Ok().finish()),
        Err(_) => Ok(HttpResponse::Ok().finish()),
    }
}

#[derive(Deserialize, Debug)]
pub struct UserProfileImageQueryParams {
    w: Option<i32>,
    h: Option<i32>,
}

pub async fn user_profile_image_handler(
    service: web::Data<AuthService<AuthRepositoryImpl>>,
    path: web::Path<i32>,
    query: web::Query<UserProfileImageQueryParams>,
) -> Result<HttpResponse, AppError> {
    let user_id = path.into_inner();
    let width = query.w.unwrap_or(500);
    let height = query.h.unwrap_or(500);
    if width <= 0 || height <= 0 {
        return Ok(HttpResponse::BadRequest().json("Invalid image dimensions."));
    }
    let profile_image_byte = service
        .get_resized_profile_image_byte(user_id, width, height)
        .await?;
    Ok(HttpResponse::Ok()
        .content_type("image/png")
        .body(profile_image_byte))
}
